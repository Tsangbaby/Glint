"""Chained fixups parser handling arm64 (fmt 2/6) and arm64e (fmt 1/3)."""
import struct

def parse(data, base_off, ncmds):
    def u32(o): return struct.unpack_from('<I', data, o)[0]
    def u64(o): return struct.unpack_from('<Q', data, o)[0]
    chained = None
    seg_vmas = []
    pos = base_off + 32
    for _ in range(ncmds):
        cmd = u32(pos); cmdsize = u32(pos+4)
        if cmd == 0x19:
            seg_vmas.append(u64(pos+24))
        elif cmd == 0x80000034:
            chained = struct.unpack_from('<II', data, pos+8)
        pos += cmdsize
    if not chained:
        return {}, {}, []
    pay = base_off + chained[0]
    ver, starts_off, imports_off, symbols_off, imports_count, imports_fmt, symbols_fmt = struct.unpack_from('<IIIIIII', data, pay)
    imports = []
    if imports_fmt == 1:
        for i in range(imports_count):
            e = u32(pay+imports_off+i*4)
            no = (e >> 9) & 0x7FFFFF
            sp = pay+symbols_off+no
            imports.append(data[sp:data.find(b'\0', sp)].decode('utf8','replace'))
    elif imports_fmt == 2:
        for i in range(imports_count):
            e = u64(pay+imports_off+i*8)
            no = (e >> 9) & 0xFFFFFFFF
            sp = pay+symbols_off+no
            imports.append(data[sp:data.find(b'\0', sp)].decode('utf8','replace'))
    rebase = {}
    bind = {}
    seg0 = seg_vmas[0]
    seg_count = u32(pay+starts_off)
    for si in range(seg_count):
        io = u32(pay+starts_off+4+si*4)
        if io == 0: continue
        p = pay+starts_off+io
        size, page_size, ptr_fmt = struct.unpack_from('<IHH', data, p)
        seg_offset = u64(p+8)
        page_count = struct.unpack_from('<H', data, p+20)[0]
        psp = p+22
        segvm = seg_vmas[si]
        for pi in range(page_count):
            start = struct.unpack_from('<H', data, psp+pi*2)[0]
            if start == 0xFFFF: continue
            loc_vm = segvm + pi*page_size + start
            while True:
                lf = base_off + (loc_vm - seg0)
                e = u64(lf)
                if ptr_fmt in (2, 6):  # 64 / 64_OFFSET
                    isbind = (e >> 63) & 1
                    nxt = (e >> 51) & 0xFFF
                    if isbind:
                        ordinal = e & 0xFFFFFF
                        if ordinal < len(imports): bind[loc_vm] = imports[ordinal]
                    else:
                        target = e & ((1 << 36) - 1)
                        rebase[loc_vm] = target + (seg0 if ptr_fmt == 6 else 0)
                    stride = 4
                else:  # arm64e 1/3/4
                    auth = (e >> 63) & 1
                    isbind = (e >> 62) & 1
                    nxt = (e >> 51) & 0x7FF
                    if isbind:
                        ordinal = e & 0xFFFF if auth else e & 0xFFFFFF
                        if ordinal < len(imports): bind[loc_vm] = imports[ordinal]
                    else:
                        if auth:
                            rebase[loc_vm] = (e & 0xFFFFFFFF) + seg0
                        else:
                            rebase[loc_vm] = (e & ((1 << 43) - 1)) + seg0
                    stride = 8 if ptr_fmt in (3,) else 4
                if nxt == 0: break
                loc_vm += nxt * stride
    return rebase, bind, imports

if __name__ == '__main__':
    import sys
    from mo import MachO
    m = MachO(sys.argv[1])
    r, b, imps = parse(m.data, m.base, m.ncmds)
    print('rebase', len(r), 'bind', len(b), 'imports', len(imps))
    for x in imps: print(' ', x)
