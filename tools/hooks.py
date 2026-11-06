import sys, struct, bisect
from capstone import *
sys.argv = [sys.argv[0], sys.argv[1]]
from dx import An

a = An(sys.argv[1])
m = a.m
base, data = a.scan_all()
md = a.md

getcls = [k for k,v in a.stub2imp.items() if v == '_objc_getClass']
hook = [k for k,v in a.stub2imp.items() if v == '_MSHookMessageEx']
selfromstr = [k for k,v in a.stub2imp.items() if v == '_NSSelectorFromString']
addm = [k for k,v in a.stub2imp.items() if v == '_class_addMethod']

reg = {}
cur_cls = None
hint = {}
last_str = {}

def rd(addr):
    b = m.read_at_addr(addr, 256)
    return b.split(b'\0')[0].decode('utf8','replace') if b else ''

for ins in md.disasm(data, base):
    op = ins.op_str
    if ins.mnemonic == 'adrp':
        try: hint[op.split(',')[0].strip()] = int(op.split('#')[1], 0)
        except Exception: pass
    elif ins.mnemonic in ('add','ldr') and ',' in op:
        parts = [p.strip() for p in op.replace(']','').split(',')]
        if len(parts) >= 2:
            src = parts[1].lstrip('[')
            if src in hint:
                imm = 0
                if len(parts) >= 3 and '#' in parts[2]:
                    try: imm = int(parts[2].split('#')[1], 0)
                    except Exception: imm = 0
                v = hint[src] + imm
                if ins.mnemonic == 'add':
                    hint[parts[0]] = v
                    last_str[parts[0]] = ('raw', v)
                else:
                    hint.pop(parts[0], None)
                    if v in a.selref: last_str[parts[0]] = ('sel', a.selref[v])
                    elif v in a.clsref: last_str[parts[0]] = ('cls', a.clsref[v])
                    elif v in a.cfstr: last_str[parts[0]] = ('cf', a.cfstr[v])
                    else: last_str[parts[0]] = ('slot', v)
    elif ins.mnemonic == 'bl':
        try: t = int(op.lstrip('#'), 0)
        except Exception: continue
        if t in getcls:
            x0 = last_str.get('x0')
            if x0 and x0[0] == 'raw':
                cur_cls = rd(x0[1]) or ('@%x' % x0[1])
            print('%08x  getClass("%s")' % (ins.address, cur_cls))
        elif t in hook:
            s = last_str.get('x1')
            sel = s[1] if s and s[0] == 'sel' else (('slot %x' % s[1]) if s else '?')
            rep = last_str.get('x2')
            rp = ('%x' % rep[1]) if rep and rep[0]=='raw' else '?'
            org = last_str.get('x3')
            og = ('%x' % org[1]) if org and org[0]=='raw' else '?'
            print('%08x  HOOK  %-38s %-58s repl=%s orig=%s' % (ins.address, cur_cls, sel, rp, og))
        elif t in addm:
            s = last_str.get('x1')
            sel = s[1] if s and s[0]=='sel' else '?'
            print('%08x  ADDMETH %-36s %s' % (ins.address, cur_cls, sel))
