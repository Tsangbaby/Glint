import sys, struct, bisect
from capstone import *
from capstone.arm64 import *
from mo import MachO
import fx
from oc import ObjC

PATH = None

class An:
    def __init__(self, path):
        self.o = ObjC(path)
        self.m = self.o.m
        m = self.m
        self.rebase, self.bind = self.o.rebase, self.o.bind
        # selectors from __objc_selrefs
        self.selref = {}
        s = m.sect('__DATA', '__objc_selrefs')
        if s:
            for i in range(s['size']//8):
                a = s['addr'] + i*8
                t = self.o.ptr(a)
                if t: self.selref[a] = m.cstr(t)
        # objc_stubs: addr -> selector
        self.stub2sel = {}
        st = m.sect('__TEXT', '__objc_stubs')
        self.md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
        self.md.detail = True
        self.md.skipdata = True
        if st:
            data = m.data[m.base+st['off']:m.base+st['off']+st['size']]
            for off in range(0, st['size'], 0x20):
                blk = data[off:off+0x20]
                a = st['addr']+off
                # adrp x1, page ; ldr x1,[x1,#imm]
                try:
                    insns = list(self.md.disasm(blk, a))
                except Exception:
                    continue
                page = None; sr = None
                for ins in insns:
                    if ins.mnemonic == 'adrp' and ins.op_str.startswith('x1,'):
                        page = int(ins.op_str.split('#')[1], 0)
                    elif ins.mnemonic == 'ldr' and page is not None and ins.op_str.startswith('x1,'):
                        try:
                            imm = int(ins.op_str.split('#')[1].rstrip(']'), 0)
                        except Exception:
                            imm = 0
                        sr = page + imm
                        break
                if sr and sr in self.selref:
                    self.stub2sel[a] = self.selref[sr]
        # __stubs -> imported symbol (via got)
        self.stub2imp = {}
        s2 = m.sect('__TEXT', '__stubs')
        if s2:
            data = m.data[m.base+s2['off']:m.base+s2['off']+s2['size']]
            for off in range(0, s2['size'], 12):
                a = s2['addr']+off
                try:
                    insns = list(self.md.disasm(data[off:off+12], a))
                except Exception: continue
                page = None
                for ins in insns:
                    if ins.mnemonic == 'adrp':
                        page = int(ins.op_str.split('#')[1], 0)
                    elif ins.mnemonic == 'ldr' and page is not None:
                        try: imm = int(ins.op_str.split('#')[1].rstrip(']'), 0)
                        except Exception: imm = 0
                        g = page+imm
                        nm = self.bind.get(g)
                        if nm: self.stub2imp[a] = nm
                        break
        # methods sorted
        self.meths = sorted([(a, n) for a, n, s in self.o.methods if a])
        self.maddrs = [x[0] for x in self.meths]
        self.funcs = sorted(self.m.funcs())
        # cfstring
        self.cfstr = {}
        cs = m.sect('__DATA_CONST', '__cfstring')
        if cs:
            for off in range(0, cs['size'], 0x20):
                a = cs['addr']+off
                raw = m.read_at_addr(a, 32)
                if len(raw) < 32: break
                isa, flags, dp, ln = struct.unpack('<QQQQ', raw)
                dp = self.rebase.get(a+16, dp)
                if dp:
                    self.cfstr[a] = m.cstr(dp)
        # classrefs
        self.clsref = {}
        cr = m.sect('__DATA', '__objc_classrefs')
        if cr:
            for i in range(cr['size']//8):
                a = cr['addr']+i*8
                bn = self.bind.get(a)
                if bn: self.clsref[a] = bn.replace('_OBJC_CLASS_$_','')
                else:
                    t = self.o.ptr(a)
                    if t:
                        for c in self.o.classes:
                            if c['addr'] == t: self.clsref[a] = c['name']

    def owner(self, addr):
        i = bisect.bisect_right(self.maddrs, addr) - 1
        mname = self.meths[i][1] if i >= 0 else '?'
        mstart = self.maddrs[i] if i >= 0 else 0
        j = bisect.bisect_right(self.funcs, addr) - 1
        fstart = self.funcs[j] if j >= 0 else 0
        if fstart > mstart:
            return '[subfunc %08x] (after %s)' % (fstart, mname)
        return mname

    def note(self, ins, hint):
        cm = []
        if ins.mnemonic in ('bl', 'b'):
            try: t = int(ins.op_str.lstrip('#'), 0)
            except Exception: t = None
            if t is not None:
                if t in self.stub2sel: cm.append('msgSend[%s]' % self.stub2sel[t])
                elif t in self.stub2imp: cm.append('IMP:%s' % self.stub2imp[t])
                else:
                    i = bisect.bisect_right(self.maddrs, t)-1
                    if i >= 0 and self.maddrs[i] == t: cm.append('-> %s' % self.meths[i][1])
                    else: cm.append('-> sub_%x' % t)
        if ins.mnemonic == 'adrp':
            try:
                reg = ins.op_str.split(',')[0].strip()
                hint[reg] = int(ins.op_str.split('#')[1], 0)
            except Exception: pass
        elif ins.mnemonic in ('add', 'ldr') and ',' in ins.op_str:
            parts = [p.strip() for p in ins.op_str.replace(']','').split(',')]
            if len(parts) >= 2:
                src = parts[1].lstrip('[')
                if src in hint:
                    imm = 0
                    if len(parts) >= 3 and '#' in parts[2]:
                        try: imm = int(parts[2].split('#')[1], 0)
                        except Exception: imm = 0
                    a = hint[src]+imm
                    d = parts[0]
                    lbl = self.label(a)
                    if lbl: cm.append(lbl)
                    if ins.mnemonic == 'add': hint[d] = a
                    else: hint.pop(d, None)
                else:
                    hint.pop(parts[0], None)
        return '  ; '+' | '.join(cm) if cm else ''

    def label(self, a):
        if a in self.selref: return 'SEL(%s)' % self.selref[a]
        if a in self.cfstr: return '@"%s"' % self.cfstr[a]
        if a in self.clsref: return 'CLS(%s)' % self.clsref[a]
        if a in self.bind: return 'GOT:%s' % self.bind[a]
        for s in self.m.sections:
            if s['addr'] <= a < s['addr']+s['size']:
                if s['name'] in ('__cstring', '__objc_methname', '__objc_classname'):
                    return 'STR("%s")' % self.m.cstr(a)
                if s['name'] == '__const' or s['seg'] == '__DATA':
                    return 'DATA(%08x/%s)' % (a, s['name'])
        return None

    def dump(self, addr, n=200):
        end = addr
        j = bisect.bisect_right(self.funcs, addr)
        if j < len(self.funcs): end = self.funcs[j]
        raw = self.m.read_at_addr(addr, min(n*4, max(4, end-addr)))
        hint = {}
        print('==== %08x  %s ====' % (addr, self.owner(addr)))
        for ins in self.md.disasm(raw, addr):
            print('%08x  %-8s %-42s%s' % (ins.address, ins.mnemonic, ins.op_str, self.note(ins, hint)))

    def raw(self, addr, n):
        raw = self.m.read_at_addr(addr, n*4)
        hint = {}
        for ins in self.md.disasm(raw, addr):
            print('%08x  %-8s %-42s%s' % (ins.address, ins.mnemonic, ins.op_str, self.note(ins, hint)))

    def scan_all(self):
        txt = self.m.sect('__TEXT','__text')
        data = self.m.data[self.m.base+txt['off']:self.m.base+txt['off']+txt['size']]
        return txt['addr'], data

    def callers(self, target):
        base, data = self.scan_all()
        out = []
        for ins in self.md.disasm(data, base):
            if ins.mnemonic in ('bl','b'):
                try: t = int(ins.op_str.lstrip('#'),0)
                except Exception: continue
                if t == target: out.append(ins.address)
        return out

    def xref_addr(self, target):
        """find adrp+add/ldr producing target"""
        base, data = self.scan_all()
        hint = {}
        out = []
        for ins in self.md.disasm(data, base):
            if ins.mnemonic == 'adrp':
                try: hint[ins.op_str.split(',')[0].strip()] = int(ins.op_str.split('#')[1],0)
                except Exception: pass
            elif ins.mnemonic in ('add','ldr','ldrsw','str') and ',' in ins.op_str:
                parts=[p.strip() for p in ins.op_str.replace(']','').split(',')]
                if len(parts)>=2:
                    src=parts[1].lstrip('[')
                    if src in hint:
                        imm=0
                        if len(parts)>=3 and '#' in parts[2]:
                            try: imm=int(parts[2].split('#')[1],0)
                            except Exception: imm=0
                        if hint[src]+imm == target: out.append((ins.address, ins.mnemonic))
                        if ins.mnemonic=='add': hint[parts[0]]=hint[src]+imm
        return out

    def selcall(self, sel):
        """find all bl to objc_stub of selector"""
        tgt = [a for a,s in self.stub2sel.items() if s == sel]
        res = []
        for t in tgt:
            for c in self.callers(t):
                res.append((c, self.owner(c)))
        return res

    def impcall(self, name):
        tgt = [a for a,s in self.stub2imp.items() if name in s]
        res = []
        for t in tgt:
            for c in self.callers(t):
                res.append((c, self.owner(c), self.stub2imp[t]))
        return res

if __name__ == '__main__':
    p = sys.argv[1]; cmd = sys.argv[2]
    a = An(p)
    if cmd == 'dump':
        a.dump(int(sys.argv[3],16), int(sys.argv[4]) if len(sys.argv)>4 else 400)
    elif cmd == 'raw':
        a.raw(int(sys.argv[3],16), int(sys.argv[4]))
    elif cmd == 'sel':
        for x,o in a.selcall(sys.argv[3]): print('%08x  %s' % (x,o))
    elif cmd == 'imp':
        for x,o,n in a.impcall(sys.argv[3]): print('%08x  %-60s %s' % (x,o,n))
    elif cmd == 'callers':
        for x in a.callers(int(sys.argv[3],16)): print('%08x  %s' % (x, a.owner(x)))
    elif cmd == 'xr':
        for x,mn in a.xref_addr(int(sys.argv[3],16)): print('%08x %-6s %s' % (x,mn,a.owner(x)))
    elif cmd == 'sels':
        for x in sorted(set(a.stub2sel.values())):
            if len(sys.argv)<4 or sys.argv[3].lower() in x.lower(): print(x)
    elif cmd == 'cf':
        for k,v in sorted(a.cfstr.items()): print('%08x %s' % (k,v))
    elif cmd == 'stubs':
        for k,v in sorted(a.stub2imp.items()): print('%08x %s' % (k,v))
    elif cmd == 'at':
        print(a.owner(int(sys.argv[3],16)))
