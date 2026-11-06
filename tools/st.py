import sys, re
d = open(sys.argv[1], 'rb').read()
mn = int(sys.argv[2]) if len(sys.argv) > 2 else 4
pat = sys.argv[3].lower() if len(sys.argv) > 3 else None
for m in re.finditer(rb'[\x20-\x7e]{%d,}' % mn, d):
    s = m.group().decode()
    if pat is None or pat in s.lower():
        print('%08x %s' % (m.start(), s))
