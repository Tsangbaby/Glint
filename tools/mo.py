import sys, struct

class MachO:
    def __init__(self, path, want_sub=None):
        self.data = open(path, 'rb').read()
        d = self.data
        magic = struct.unpack('>I', d[:4])[0]
        self.base = 0
        if magic in (0xcafebabe, 0xcafebabf):
            n = struct.unpack('>I', d[4:8])[0]
            offs = []
            for i in range(n):
                o = 8 + i*20
                ct, cs, off, size, align = struct.unpack('>iiIII', d[o:o+20])
                offs.append((ct, cs, off, size))
            self.slices = offs
            pick = offs[0]
            for ct, cs, off, size in offs:
                if ct == 0x100000C:
                    if want_sub is None or cs == want_sub:
                        pick = (ct, cs, off, size); break
            self.base = pick[2]
            self.cpusub = pick[1]
        else:
            self.slices = None
            self.cpusub = struct.unpack('<i', d[8:12])[0]
        b = self.base
        self.magic32 = struct.unpack('<I', d[b:b+4])[0]
        self.ncmds = struct.unpack('<I', d[b+16:b+20])[0]
        self.filetype = struct.unpack('<I', d[b+12:b+16])[0]
        self.cmds = []
        self.segs = []
        self.sections = []
        self.dylibs = []
        self.symtab = None
        self.func_starts = None
        self.chained = None
        self.dyldinfo = None
        off = b + 32
        for i in range(self.ncmds):
            cmd, sz = struct.unpack('<II', d[off:off+8])
            self.cmds.append((cmd, sz, off))
            if cmd == 0x19:
                segname = d[off+8:off+24].rstrip(b'\0').decode()
                vmaddr, vmsize, fileoff, filesize = struct.unpack('<QQQQ', d[off+24:off+56])
                nsects = struct.unpack('<I', d[off+64:off+68])[0]
                self.segs.append(dict(name=segname, vmaddr=vmaddr, vmsize=vmsize, fileoff=fileoff, filesize=filesize))
                for j in range(nsects):
                    so = off + 72 + j*80
                    sn = d[so:so+16].rstrip(b'\0').decode()
                    sg = d[so+16:so+32].rstrip(b'\0').decode()
                    addr, size = struct.unpack('<QQ', d[so+32:so+48])
                    foff, align, reloff, nreloc, flags = struct.unpack('<IIIII', d[so+48:so+68])
                    self.sections.append(dict(seg=sg, name=sn, addr=addr, size=size, off=foff, flags=flags, reserved1=struct.unpack('<I', d[so+68:so+72])[0], reserved2=struct.unpack('<I', d[so+72:so+76])[0]))
            elif cmd == 0x2:
                symoff, nsyms, stroff, strsize = struct.unpack('<IIII', d[off+8:off+24])
                self.symtab = (symoff, nsyms, stroff, strsize)
            elif cmd == 0x26:
                fo, fs = struct.unpack('<II', d[off+8:off+16])
                self.func_starts = (fo, fs)
            elif cmd == 0x80000034:
                fo, fs = struct.unpack('<II', d[off+8:off+16])
                self.chained = (fo, fs)
            elif cmd in (0x80000022, 0x22):
                self.dyldinfo = off
            elif cmd in (0xc, 0x8000001f, 0xd, 0x18, 0x20):
                no = struct.unpack('<I', d[off+8:off+12])[0] if cmd in (0xc,0x8000001f,0xd,0x18,0x20) else 0
                try:
                    nm = d[off+24:off+sz].split(b'\0')[0].decode()
                except Exception:
                    nm = '?'
                self.dylibs.append(nm)
            off += sz

    def sect(self, seg, name):
        for s in self.sections:
            if s['seg'] == seg and s['name'] == name:
                return s
        return None

    def read_at_addr(self, addr, n):
        for s in self.segs:
            if s['vmaddr'] <= addr < s['vmaddr'] + s['vmsize'] and s['filesize']:
                o = self.base + s['fileoff'] + (addr - s['vmaddr'])
                return self.data[o:o+n]
        return b''

    def a2o(self, addr):
        for s in self.segs:
            if s['vmaddr'] <= addr < s['vmaddr'] + s['vmsize'] and s['filesize']:
                return self.base + s['fileoff'] + (addr - s['vmaddr'])
        return None

    def cstr(self, addr):
        b = self.read_at_addr(addr, 512)
        return b.split(b'\0')[0].decode('utf8', 'replace')

    def syms(self):
        out = []
        if not self.symtab: return out
        symoff, nsyms, stroff, strsize = self.symtab
        d = self.data; b = self.base
        for i in range(nsyms):
            o = b + symoff + i*16
            strx, ntype, sect, desc = struct.unpack('<IBBH', d[o:o+8])
            val = struct.unpack('<Q', d[o+8:o+16])[0]
            nm = d[b+stroff+strx:].split(b'\0')[0].decode('utf8','replace')
            out.append((nm, ntype, sect, val))
        return out

    def funcs(self):
        if not self.func_starts: return []
        fo, fs = self.func_starts
        d = self.data[self.base+fo:self.base+fo+fs]
        txt = self.sect('__TEXT','__text')
        addr = txt['addr'] if txt else self.segs[0]['vmaddr']
        # actually base is __TEXT vmaddr
        addr = self.segs[0]['vmaddr'] if self.segs[0]['name']=='__TEXT' else addr
        res = []
        i = 0
        cur = addr
        while i < len(d):
            v = 0; sh = 0
            while True:
                if i >= len(d): break
                byte = d[i]; i += 1
                v |= (byte & 0x7f) << sh
                if not (byte & 0x80): break
                sh += 7
            if v == 0: break
            cur += v
            res.append(cur)
        return res

if __name__ == '__main__':
    m = MachO(sys.argv[1])
    print('slices:', [(hex(a),hex(b&0xffffffff),hex(c)) for a,b,c,_ in (m.slices or [])])
    print('filetype', m.filetype, 'ncmds', m.ncmds, 'base', hex(m.base), 'cpusub', hex(m.cpusub&0xffffffff))
    print('chained', m.chained, 'dyldinfo', m.dyldinfo)
    print('--- segs ---')
    for s in m.segs: print(' %-12s vm=%08x size=%08x' % (s['name'], s['vmaddr'], s['vmsize']))
    print('--- sections ---')
    for s in m.sections: print(' %-16s %-20s addr=%08x size=%08x off=%08x' % (s['seg'], s['name'], s['addr'], s['size'], s['off']))
    print('--- dylibs ---')
    for x in m.dylibs: print(' ', x)
