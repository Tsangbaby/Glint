"""Generate ObjC headers from objc_full.txt (class-dump with full type encodings)."""
import re, sys, os
from collections import OrderedDict

SRC = sys.argv[1] if len(sys.argv) > 1 else '../work/objc_full.txt'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'Headers'

SIMPLE = {
    'v': 'void', 'B': 'BOOL', 'c': 'char', 'C': 'unsigned char', 's': 'short',
    'S': 'unsigned short', 'i': 'int', 'I': 'unsigned int', 'l': 'long',
    'L': 'unsigned long', 'q': 'long long', 'Q': 'unsigned long long',
    'f': 'float', 'd': 'double', '*': 'char *', '#': 'Class', ':': 'SEL',
}
STRUCTS = {
    'CGRect': 'CGRect', 'CGPoint': 'CGPoint', 'CGSize': 'CGSize',
    'UIEdgeInsets': 'UIEdgeInsets', 'CGAffineTransform': 'CGAffineTransform',
    'NSRange': 'NSRange', 'CATransform3D': 'CATransform3D',
}

# Hand-curated refinements recovered by reading the disassembly
# (class, selector) -> (return type, [param types])
OVERRIDE = {
    ('GLTController', 'sharedController'): ('GLTController *', []),
    ('GLTController', 'moveWindowToScene:'): ('void', ['UIWindowScene *']),
    ('GLTController', 'keyboardFrameChanged:'): ('void', ['NSNotification *']),
    ('GLTController', 'showConnection:connected:'): ('void', ['GLTDevice *', 'BOOL']),
    ('GLTController', 'showNotification:'): ('void', ['GLTNotification *']),
    ('GLTController', 'registerClockView:dateView:'): ('void', ['UIView *', 'UIView *']),
    ('GLTController', 'frameOfClock:'): ('CGRect', ['UIView *']),
    ('GLTController', 'openPlatter:'): ('void', ['GLTPlatterContent *']),
    ('GLTController', 'closePlatterAnimated:'): ('void', ['BOOL']),
    ('GLTController', 'clockLongPressed:'): ('void', ['UILongPressGestureRecognizer *']),
    ('GLTController', 'pickerRowForPill:font:'): ('UIView *', ['NSInteger', 'UIFont *']),
    ('GLTController', 'pickerCellForPill:font:width:'): ('UIView *', ['NSInteger', 'UIFont *', 'CGFloat']),
    ('GLTController', 'pickerRowTapped:'): ('void', ['UITapGestureRecognizer *']),
    ('GLTController', 'contentForPill:'): ('GLTPillContent *', ['NSInteger']),
    ('GLTController', 'stringForUpcomingDate:'): ('NSString *', ['NSDate *']),
    ('GLTController', 'countContent:singular:plural:none:symbol:'):
        ('GLTPillContent *', ['NSInteger', 'NSString *', 'NSString *', 'NSString *', 'NSString *']),
    ('GLTController', 'speed:'): ('NSString *', ['double']),
    ('GLTController', 'updateAfter:'): ('void', ['double']),
    ('GLTController', 'showVolume:'): ('void', ['float']),
    ('GLTPillContent', 'contentWithSymbol:text:'): ('GLTPillContent *', ['NSString *', 'NSString *']),
    ('GLTPillContent', 'attributedStringWithFont:color:'): ('NSAttributedString *', ['UIFont *', 'UIColor *']),
    ('GLTClock', 'isStyled:'): ('BOOL', ['UIView *']),
    ('GLTClock', 'outsetForLabel:'): ('double', ['UIView *']),
    ('GLTClock', 'backgroundForLabel:create:'): ('UIView *', ['UIView *', 'BOOL']),
    ('GLTClock', 'layoutBackgroundOfLabel:'): ('void', ['UIView *']),
    ('GLTClock', 'visibleDateOfLabel:'): ('NSDate *', ['UIView *']),
    ('GLTClock', 'paddingForLabel:'): ('UIEdgeInsets', ['UIView *']),
    ('GLTClock', 'setCompanion:forLabel:'): ('void', ['UIView *', 'UIView *']),
    ('GLTClock', 'ownerOfLabel:'): ('UIView *', ['UIView *']),
    ('GLTClock', 'setSystemText:forLabel:'): ('void', ['NSString *', 'UIView *']),
    ('GLTClock', 'apply:toLabel:background:textColor:'):
        ('void', ['GLTPillContent *', 'UILabel *', 'UIColor *', 'UIColor *']),
    ('GLTClock', 'apply:toLabel:background:textColor:animated:'):
        ('void', ['GLTPillContent *', 'UILabel *', 'UIColor *', 'UIColor *', 'BOOL']),
    ('GLTClock', 'fadeOutSnapshotOfLabel:'): ('void', ['UIView *']),
    ('GLTClock', 'fadeInLabel:'): ('void', ['UIView *']),
    ('GLTClock', 'popLabel:'): ('void', ['UIView *']),
    ('GLTPlatterContent', 'fillWith:'): ('void', ['NSArray *']),
    ('GLTPlatterView', 'heightForWidth:'): ('double', ['double']),
    ('GLTPlatterView', 'setContent:'): ('void', ['GLTPlatterContent *']),
    ('GLTMediaPlatterView', 'controlWithSymbol:size:action:'):
        ('UIButton *', ['NSString *', 'double', 'SEL']),
    ('GLTRemindersPlatterView', 'complete:'): ('void', ['UIButton *']),
    ('GLTComposePlatterView', 'showSuggestions:'): ('void', ['NSString *']),
    ('GLTComposePlatterView', 'chooseRecipient:'): ('void', ['GLTRecipient *']),
    ('GLTComposePlatterView', 'showStatus:'): ('void', ['NSString *']),
    ('GLTComposePlatterView', 'composeWithApple:text:'): ('void', ['BOOL', 'NSString *']),
    ('GLTComposePlatterView', 'messageComposeViewController:didFinishWithResult:'):
        ('void', ['MFMessageComposeViewController *', 'NSInteger']),
    ('GLTMedia', 'sharedMedia'): ('GLTMedia *', []),
    ('GLTEvents', 'sharedEvents'): ('GLTEvents *', []),
    ('GLTEvents', 'completeReminder:'): ('void', ['EKReminder *']),
    ('GLTClockItems', 'sharedItems'): ('GLTClockItems *', []),
    ('GLTUnlocks', 'sharedUnlocks'): ('GLTUnlocks *', []),
    ('GLTUnlocks', 'lockStateChanged:'): ('void', ['int']),
    ('GLTWeather', 'sharedWeather'): ('GLTWeather *', []),
    ('GLTWeather', 'refreshForcing:'): ('void', ['BOOL']),
    ('GLTWeather', 'symbolForCode:isDay:'): ('NSString *', ['NSInteger', 'BOOL']),
    ('GLTWeather', 'descriptionForCode:'): ('NSString *', ['NSInteger']),
    ('GLTWeather', 'temperatureString:'): ('NSString *', ['double']),
    ('GLTWeather', 'nextSunEvent:'): ('NSDate *', ['BOOL *']),
    ('GLTWeather', 'applyForecast:place:'): ('void', ['NSDictionary *', 'NSString *']),
    ('GLTWeather', 'fetchForLocation:place:'): ('void', ['CLLocation *', 'NSString *']),
    ('GLTWeather', 'locationManager:didUpdateLocations:'): ('void', ['CLLocationManager *', 'NSArray *']),
    ('GLTWeather', 'locationManager:didFailWithError:'): ('void', ['CLLocationManager *', 'NSError *']),
    ('GLTWeather', 'locationManagerDidChangeAuthorization:'): ('void', ['CLLocationManager *']),
    ('GLTPrefs', 'sharedPrefs'): ('GLTPrefs *', []),
    ('GLTPrefs', 'pillOrder'): ('NSArray *', []),
    ('GLTPrefs', 'nameForPill:'): ('NSString *', ['NSInteger']),
    ('GLTPrefs', 'symbolForPill:'): ('NSString *', ['NSInteger']),
    ('GLTPrefs', 'boolForKey:fallback:'): ('BOOL', ['NSString *', 'BOOL']),
    ('GLTPrefs', 'doubleForKey:fallback:min:max:'):
        ('double', ['NSString *', 'double', 'double', 'double']),
    ('GLTPrefs', 'objectForKey:'): ('id', ['NSString *']),
    ('GLTPrefs', 'setPill:'): ('void', ['NSInteger']),
    ('GLTWindow', 'hitTest:withEvent:'): ('UIView *', ['CGPoint', 'UIEvent *']),
    ('GLTPickerList', 'hitTest:withEvent:'): ('UIView *', ['CGPoint', 'UIEvent *']),
}

OVERRIDE.update({
    ('GLTController', 'visibleClock'): ('UIView *', []),
    ('GLTController', 'pillContent'): ('GLTPillContent *', []),
    ('GLTController', 'shownKind'): ('NSString *', []),
    ('GLTController', 'batteryContent'): ('GLTPillContent *', []),
    ('GLTController', 'mediaContent'): ('GLTPillContent *', []),
    ('GLTController', 'weatherContent'): ('GLTPillContent *', []),
    ('GLTController', 'alarmContent'): ('GLTPillContent *', []),
    ('GLTController', 'nextEventContent'): ('GLTPillContent *', []),
    ('GLTController', 'storageContent'): ('GLTPillContent *', []),
    ('GLTController', 'countdownContent'): ('GLTPillContent *', []),
    ('GLTController', 'sunContent'): ('GLTPillContent *', []),
    ('GLTController', 'cutout'): ('double', []),
    ('GLTController', 'platterContent'): ('GLTPlatterContent *', []),
    ('GLTController', 'eventsLeftToday'): ('NSInteger', []),
    ('GLTController', 'currentPill'): ('NSInteger', []),
    ('GLTController', 'showsPlainTime'): ('BOOL', []),
    ('GLTController', 'layoutTouchView'): ('void', []),
    ('GLTPlaylist', 'x'): ('id', []),
})


def parse_type(s, i=0):
    """Return (objc_type_string, next_index)."""
    if i >= len(s):
        return 'id', i
    c = s[i]
    if c in 'rnNoORV':                     # qualifiers
        return parse_type(s, i + 1)
    if c == '^':
        inner, j = parse_type(s, i + 1)
        return inner + ' *', j
    if c == '@':
        if s.startswith('@"', i):
            j = s.index('"', i + 2)
            cls = s[i + 2:j]
            return cls + ' *', j + 1
        if s.startswith('@?', i):
            return 'id /* block */', i + 2
        return 'id', i + 1
    if c == '{':
        # {Name=....}
        depth = 0
        j = i
        while j < len(s):
            if s[j] == '{':
                depth += 1
            elif s[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = s[i + 1:j]
        name = body.split('=')[0]
        return STRUCTS.get(name, name), j + 1
    if c in SIMPLE:
        return SIMPLE[c], i + 1
    return 'id', i + 1


def parse_signature(enc):
    """'v24@0:8@16' -> (rettype, [(type, selpart)])"""
    ret, i = parse_type(enc, 0)
    # skip frame size digits
    while i < len(enc) and enc[i].isdigit():
        i += 1
    args = []
    while i < len(enc):
        t, i = parse_type(enc, i)
        while i < len(enc) and enc[i].isdigit():
            i += 1
        args.append(t)
    return ret, args


def build_decl(name, ret, args):
    """name like 'apply:toLabel:background:textColor:animated:'"""
    parts = [p for p in name.split(':') if p != '']
    nargs = name.count(':')
    sel_args = args[2:]                       # drop self, _cmd
    return _decl(name, ret, [sel_args[k] if k < len(sel_args) else 'id'
                             for k in range(nargs)], parts)


def build_decl_from(name, ret, ptypes):
    parts = [p for p in name.split(':') if p != '']
    return _decl(name, ret, ptypes, parts)


def _decl(name, ret, ptypes, parts):
    if ret == 'id' and name == 'init':
        ret = 'instancetype'
    if not ptypes:
        return '(%s)%s' % (ret, name)
    out = []
    for k, t in enumerate(ptypes):
        part = parts[k] if k < len(parts) else ''
        if k == 0:
            out.append('(%s)%s:(%s)arg%d' % (ret, part, t, k + 1))
        else:
            out.append('%s:(%s)arg%d' % (part, t, k + 1))
    return ' '.join(out)


def main():
    classes = OrderedDict()
    cur = None
    for line in open(SRC, encoding='utf8'):
        line = line.rstrip('\n')
        m = re.match(r'^=== (\S+) : (\S+)\s+\(instsize (\d+)\)', line)
        if m:
            cur = dict(name=m.group(1), super=m.group(2), size=int(m.group(3)),
                       ivars=[], methods=[], cmethods=[])
            classes[cur['name']] = cur
            continue
        if cur is None:
            continue
        m = re.match(r'^    ivar (\S+)\s+(\S*)\s+offvar=\S+ off=(\d+)', line)
        if m:
            tn, _ = parse_type(m.group(2) if m.group(2) else '@')
            cur['ivars'].append((tn, m.group(1), int(m.group(3))))
            continue
        m = re.match(r'^    ([0-9a-f]{8}) ([+-])\[(\S+) (\S+)\]\s*(.*)$', line)
        if m:
            sign, nm, enc = m.group(2), m.group(4), m.group(5).strip()
            if not enc or nm == '.cxx_destruct':
                continue
            ret, args = parse_signature(enc)
            ov = OVERRIDE.get((cur['name'], nm))
            if ov:
                ret, ptypes = ov
                decl = build_decl_from(nm, ret, ptypes)
            else:
                decl = build_decl(nm, ret, args)
            (cur['cmethods'] if sign == '+' else cur['methods']).append((nm, decl))
    os.makedirs(OUT, exist_ok=True)
    for name, c in classes.items():
        lines = ['//', '//  %s.h' % name, '//  Glint (reconstructed interface)', '//',
                 '//  Recovered from ObjC metadata of Glint.dylib 1.6.3', '//',
                 '', '#import <Foundation/Foundation.h>', '#import <UIKit/UIKit.h>',
                 '#import <CoreGraphics/CoreGraphics.h>', '']
        sup = c['super']
        if sup in classes:
            lines.append('#import "%s.h"' % sup)
        lines.append('')
        lines.append('@interface %s : %s' % (name, sup))
        # ivars
        lines.append('{')
        declared = set()
        inst = name
        while inst in classes:                 # include inherited ivars for layout doc
            for tn, ivn, off in classes[inst]['ivars']:
                if ivn in declared:
                    continue
                declared.add(ivn)
                lines.append('    %-30s %-4s // 0x%02x' % (tn, ivn + ';', off))
            inst = classes[inst]['super']
        lines.append('}')
        # build ivar type lookup (own + inherited)
        ivty = {}
        inst = name
        while inst in classes:
            for tn, ivn, off in classes[inst]['ivars']:
                ivty.setdefault(ivn, tn)
            inst = classes[inst]['super']
        # properties (getter + setter pair)
        mnames = {n: d for n, d in c['methods']}
        skip = set()
        props = []
        for n, d in c['methods']:
            if n in skip:
                continue
            cap = n[0].upper() + n[1:]
            setter = 'set' + cap + ':'
            if setter in mnames and n.count(':') == 0:
                it = ivty.get('_' + n)
                ty = it if it else (d[1:].split(')')[0] if d.startswith('(') else 'id')
                attr = 'copy' if ty.endswith('*') and ty.split(' ')[0] in (
                    'NSString', 'NSArray', 'NSDictionary', 'NSAttributedString') else 'strong'
                if ty in ('BOOL', 'char', 'int', 'long long', 'unsigned long long',
                          'float', 'double', 'NSInteger', 'CGRect', 'CGPoint', 'CGSize'):
                    attr = 'assign'
                if ty == 'id' and 'block' in d:
                    attr, ty = 'copy', 'id'
                props.append('@property (nonatomic, %s) %s %s;' % (attr, ty, n))
                skip.add(n)
                skip.add(setter)
        # read-only properties: getter only, name matches an ivar
        for n, d in c['methods']:
            if n in skip or n.count(':') or '_' + n not in ivty:
                continue
            if n.startswith('set') or n in ('description', 'debugDescription', 'hash', 'superclass'):
                continue
            ty = ivty['_' + n]
            attr = 'assign' if ty in ('BOOL', 'char', 'int', 'long long',
                                      'unsigned long long', 'float', 'double',
                                      'NSInteger', 'CGRect', 'CGPoint', 'CGSize') else 'strong'
            props.append('@property (nonatomic, %s, readonly) %s %s;' % (attr, ty, n))
            skip.add(n)
        lines.append('')
        for p in props:
            lines.append(p)
        if props:
            lines.append('')
        lines.append('#pragma mark - class methods')
        for n, d in c['cmethods']:
            lines.append('+ %s;' % d)
        if c['cmethods']:
            lines.append('')
        lines.append('#pragma mark - instance methods')
        for n, d in c['methods']:
            if n in skip:
                continue
            lines.append('- %s;' % d)
        lines.append('')
        lines.append('@end')
        lines.append('')
        open(os.path.join(OUT, name + '.h'), 'w', encoding='utf8').write('\n'.join(lines))
    print('generated %d headers' % len(classes))
    for name, c in classes.items():
        print('  %-26s %2d ivars %2d methods' % (name, len(c['ivars']), len(c['methods']) + len(c['cmethods'])))


main()
