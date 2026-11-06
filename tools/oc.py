import sys, struct
from mo import MachO
import fx

class ObjC:
    def __init__(self, path):
        self.m = MachO(path)
        m = self.m
        self.rebase, self.bind, self.imports = fx.parse(m.data, m.base, m.ncmds)
        self.classes = []
        self.methods = []   # (addr, name)
        self.ivars = []     # (cls, name, type, offvar)
        self._parse()

    def ptr(self, addr):
        """resolve pointer stored at addr"""
        if addr in self.rebase: return self.rebase[addr]
        if addr in self.bind: return None
        v = self.m.read_at_addr(addr, 8)
        if len(v) < 8: return None
        return struct.unpack('<Q', v)[0]

    def bname(self, addr):
        return self.bind.get(addr)

    def _parse(self):
        m = self.m
        cl = m.sect('__DATA_CONST', '__objc_classlist')
        if not cl: return
        n = cl['size'] // 8
        for i in range(n):
            ca = self.ptr(cl['addr'] + i*8)
            if not ca: continue
            self._cls(ca, False)

    def _cls(self, ca, meta):
        m = self.m
        raw = m.read_at_addr(ca, 40)
        if len(raw) < 40: return
        isa, superc, cache, vtbl, dataptr = struct.unpack('<QQQQQ', raw)
        data = self.ptr(ca+32)
        if data is None: return
        data &= ~7
        ro = m.read_at_addr(data, 72)
        if len(ro) < 72: return
        flags, istart, isize, res = struct.unpack('<IIII', ro[:16])
        nameptr = self.ptr(data+24)
        name = m.cstr(nameptr) if nameptr else '?'
        supername = None
        sp = self.ptr(ca+8)
        if sp:
            sd = self.ptr(sp+32)
            if sd:
                np = self.ptr((sd & ~7)+24)
                if np: supername = m.cstr(np)
        if not supername:
            bn = self.bname(ca+8)
            if bn: supername = bn.replace('_OBJC_CLASS_$_','')
        methods = self.ptr(data+32)
        ivars = self.ptr(data+48)
        mlist = []
        if methods:
            mlist = self._methlist(methods, name, meta)
        ivlist = []
        if ivars and not meta:
            ivlist = self._ivarlist(ivars, name)
        self.classes.append(dict(addr=ca, name=name, super=supername, methods=mlist, ivars=ivlist, meta=meta, instsize=isize))
        # metaclass
        if not meta:
            ma = self.ptr(ca)
            if ma: self._cls(ma, True)

    def _methlist(self, la, clsname, meta):
        m = self.m
        hdr = m.read_at_addr(la, 8)
        if len(hdr) < 8: return []
        entsize, count = struct.unpack('<II', hdr)
        rel = bool(entsize & 0x80000000)
        es = entsize & 0xFFFC
        out = []
        for i in range(count):
            eo = la + 8 + i*es
            if rel:
                raw = m.read_at_addr(eo, 12)
                if len(raw) < 12: break
                nrel, trel, irel = struct.unpack('<iii', raw)
                nameslot = eo + nrel
                np = self.ptr(nameslot)
                nm = m.cstr(np) if np else '?'
                imp = eo + 8 + irel
                tp = eo + 4 + trel
            else:
                raw = m.read_at_addr(eo, 24)
                if len(raw) < 24: break
                np = self.ptr(eo)
                nm = m.cstr(np) if np else '?'
                imp = self.ptr(eo+16)
                tp = self.ptr(eo+8)
            sig = m.cstr(tp) if tp else ''
            pre = '+' if meta else '-'
            full = '%s[%s %s]' % (pre, clsname, nm)
            out.append((imp, full, sig))
            self.methods.append((imp, full, sig))
        return out

    def _ivarlist(self, la, clsname):
        m = self.m
        hdr = m.read_at_addr(la, 8)
        entsize, count = struct.unpack('<II', hdr)
        out = []
        for i in range(count):
            eo = la + 8 + i*entsize
            offvar = self.ptr(eo)
            np = self.ptr(eo+8)
            tp = self.ptr(eo+16)
            nm = m.cstr(np) if np else '?'
            ty = m.cstr(tp) if tp else ''
            offval = None
            if offvar:
                b = m.read_at_addr(offvar, 4)
                if len(b) == 4: offval = struct.unpack('<I', b)[0]
            out.append((nm, ty, offvar, offval))
            self.ivars.append((clsname, nm, ty, offvar, offval))
        return out

if __name__ == '__main__':
    o = ObjC(sys.argv[1])
    for c in o.classes:
        if c['meta']: continue
        print('=== %s : %s  (instsize %d) @%08x' % (c['name'], c['super'], c['instsize'], c['addr']))
        for nm, ty, ov, ovv in c['ivars']:
            print('    ivar %-40s %-30s offvar=%08x off=%s' % (nm, ty, ov or 0, ovv))
        for imp, full, sig in c['methods']:
            print('    %08x %-70s %s' % (imp or 0, full, sig))
        for cc in o.classes:
            if cc['meta'] and cc['name'] == c['name']:
                for imp, full, sig in cc['methods']:
                    print('    %08x %-70s %s' % (imp or 0, full, sig))
