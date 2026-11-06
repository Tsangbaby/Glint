"""Per-function semantic fingerprint: selectors, imports, strings, numeric constants."""
import sys, struct, bisect, json
from capstone import *
from capstone.arm64 import *
from mo import MachO
import fx
from oc import ObjC
from dx import An


def imm_float(ins):
    """decode fmov dN, #imm / mov w, #imm ... ; fmov sN, wM"""
    return None


def main(path, outpath):
    a = An(path)
    funcs = sorted(a.funcs)
    # owner map
    res = {}
    txt = a.m.sect('__TEXT', '__text')
    end_all = txt['addr'] + txt['size']
    for idx, start in enumerate(funcs):
        end = funcs[idx+1] if idx+1 < len(funcs) else end_all
        if end <= start or end - start > 0x4000:
            continue
        raw = a.m.read_at_addr(start, end-start)
        if not raw:
            continue
        hint = {}
        sels, imps, strs, data_refs = [], [], [], []
        last_mov = {}
        for ins in a.md.disasm(raw, start):
            mn, ops = ins.mnemonic, ins.op_str
            if mn in ('bl', 'b'):
                try:
                    t = int(ops.lstrip('#'), 0)
                except Exception:
                    t = None
                if t is not None:
                    if t in a.stub2sel:
                        sels.append(a.stub2sel[t])
                    elif t in a.stub2imp:
                        imps.append(a.stub2imp[t])
            if mn == 'adrp':
                try:
                    hint[ops.split(',')[0].strip()] = int(ops.split('#')[1], 0)
                except Exception:
                    pass
            elif mn in ('add', 'ldr', 'ldrb', 'ldrh', 'ldrsw', 'str') and ',' in ops:
                parts = [p.strip() for p in ops.replace(']', '').split(',')]
                if len(parts) >= 2:
                    src = parts[1].lstrip('[')
                    if src in hint:
                        imm = 0
                        if len(parts) >= 3 and '#' in parts[2]:
                            try:
                                imm = int(parts[2].split('#')[1], 0)
                            except Exception:
                                imm = 0
                        addr = hint[src] + imm
                        lbl = a.label(addr)
                        if lbl:
                            if lbl.startswith('@"'):
                                strs.append(lbl[2:-1])
                            elif lbl.startswith('STR('):
                                strs.append(lbl[5:-2])
                            elif lbl.startswith('SEL('):
                                sels.append('@sel:' + lbl[4:-1])
                            elif lbl.startswith('GOT:'):
                                imps.append(lbl[4:])
                            elif lbl.startswith('CLS('):
                                imps.append('@cls:' + lbl[4:-1])
                            elif lbl.startswith('DATA('):
                                data_refs.append(lbl)
                        if mn == 'add':
                            hint[parts[0]] = addr
                        else:
                            hint.pop(parts[0], None)
            # float immediate via fmov dN, #x
            if mn == 'fmov' and '#' in ops:
                try:
                    v = float(ops.split('#')[1].split(']')[0])
                    sels.append('@f:%g' % v)
                except Exception:
                    pass
            # mov w8, #imm then movk / fmov s0, w8
            if mn == 'mov' and ops.startswith('w') and '#' in ops:
                try:
                    reg = ops.split(',')[0].strip()
                    last_mov[reg] = int(ops.split('#')[1], 0)
                except Exception:
                    pass
            if mn == 'movk' and ops.startswith('w') and '#' in ops:
                try:
                    parts = [p.strip() for p in ops.split(',')]
                    reg = parts[0]
                    v = int(parts[1].lstrip('#'), 0)
                    sh = 0
                    if len(parts) > 2 and 'lsl' in parts[2]:
                        sh = int(parts[2].split('#')[1], 0)
                    if reg in last_mov:
                        last_mov[reg] |= (v << sh)
                except Exception:
                    pass
            if mn == 'fmov' and ',' in ops and not '#' in ops:
                parts = [p.strip() for p in ops.split(',')]
                if len(parts) == 2 and parts[0].startswith('s') and parts[1].startswith('w'):
                    if parts[1] in last_mov:
                        bits = last_mov[parts[1]] & 0xffffffff
                        f = struct.unpack('<f', struct.pack('<I', bits))[0]
                        sels.append('@f32:%g' % f)
        # de-dup preserving order
        def uniq(x):
            seen = set(); o = []
            for i in x:
                if i not in seen:
                    seen.add(i); o.append(i)
            return o
        res[start] = dict(name=a.owner(start), end=end,
                          sels=uniq([s for s in sels if not s.startswith('@')]),
                          floats=uniq([s for s in sels if s.startswith('@f')]),
                          imps=uniq(imps), strs=uniq(strs))
    return res
    return res


if __name__ == '__main__':
    p = sys.argv[1]
    r = main(p, None)
    with open(sys.argv[2], 'w', encoding='utf8') as f:
        for addr in sorted(r):
            v = r[addr]
            f.write('\n### %08x  %s   (size %d)\n' % (addr, v['name'], v['end']-addr))
            if v['sels']:
                f.write('  SEL: %s\n' % ', '.join(v['sels']))
            if v['floats']:
                f.write('  NUM: %s\n' % ', '.join(v['floats']))
            if v['imps']:
                f.write('  IMP: %s\n' % ', '.join(v['imps']))
            if v['strs']:
                f.write('  STR: %s\n' % ' | '.join(v['strs']))
    print('functions', len(r))
