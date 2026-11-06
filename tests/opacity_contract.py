"""Exact inverses for the authorized background-transparency addition."""
ROW = {'defaults':'com.antonym.glint','cell':'PSDefaultCell','cellClass':'GLTSliderCell',
       'label':'Background Transparency','key':'backgroundTransparency','min':0,'max':100,
       'step':5,'default':0,'format':'%.0f%%','PostNotification':'com.antonym.glint/reload'}
HELPER = '''static double GLTBackgroundOpacity(double transparency) {
    if (!isfinite(transparency)) return 1.0;
    return 1.0 - fmax(0.0, fmin(100.0, transparency)) / 100.0;
}

'''
CLOCK_METHODS = '''+ (UIColor *)systemTextColorForLabel:(UILabel *)label {
    return objc_getAssociatedObject(label, &kGLTSystemTextColorKey);
}

+ (UIColor *)foregroundColorForLabel:(UILabel *)label {
    GLTPrefs *prefs = [GLTPrefs sharedPrefs];
    if (prefs.backgroundOpacity == 0.0) {
        return [self systemTextColorForLabel:label] ?: label.textColor ?: prefs.textColor;
    }
    return prefs.textColor;
}

+ (void)setSystemTextColor:(UIColor *)color forLabel:(UILabel *)label {
    if (!color) return;
    objc_setAssociatedObject(label, &kGLTSystemTextColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!_rendering && [self isStyled:label] && [GLTPrefs sharedPrefs].backgroundOpacity == 0.0) {
        NSMutableAttributedString *string = [label.attributedText mutableCopy];
        if (string.length) {
            [string addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, string.length)];
            _rendering = YES;
            label.attributedText = string;
            _rendering = NO;
        }
    }
}

'''
EDITS = {
 'Headers/GLTPrefs.h': [('', '@property (nonatomic, assign, readonly) double backgroundOpacity;\n',1)],
 'Headers/GLTClock.h': [('', '+ (UIColor *)systemTextColorForLabel:(UILabel *)label;\n+ (UIColor *)foregroundColorForLabel:(UILabel *)label;\n+ (void)setSystemTextColor:(UIColor *)color forLabel:(UILabel *)label;\n',1)],
 'Sources/GLTPrefs.m': [('', '@property (nonatomic, readwrite) double backgroundOpacity;\n',1),
                      ('',HELPER,1),('', '    _backgroundOpacity = GLTBackgroundOpacity([self doubleForKey:@"backgroundTransparency" fallback:0 min:0 max:100]);\n',1)],
 'Sources/GLTClock.m': [('', 'static char kGLTSystemTextColorKey;\n',1),('', CLOCK_METHODS,1),
                      ('','            [self setSystemTextColor:label.textColor forLabel:label];\n',1),
                      ('','        textColor = [self foregroundColorForLabel:label];\n',1),
                      ('','    UIColor *systemColor = [self systemTextColorForLabel:label];\n    if (systemColor) label.textColor = systemColor;\n    objc_setAssociatedObject(label, &kGLTSystemTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);\n',1)],
 'Sources/GLTController.m': [('', '    background = [background colorWithAlphaComponent:CGColorGetAlpha(background.CGColor) * prefs.backgroundOpacity];\n',1),
                           ('','    preview.backgroundColor = [preview.backgroundColor colorWithAlphaComponent:CGColorGetAlpha(preview.backgroundColor.CGColor) * prefs.backgroundOpacity];\n',2)],
 'Tweak.xm': [('', '        [GLTClock setSystemTextColor:color forLabel:self];\n',1),
              ('[GLTPrefs sharedPrefs].textColor','[GLTClock foregroundColorForLabel:self]',2)],
}


def inverse_opacity(text, path):
    for before, after, count in reversed(EDITS.get(path, [])):
        if text.count(after) != count:
            raise AssertionError('opacity inverse count mismatch: '+path+' '+repr(after))
        text = text.replace(after, before)
    return text


def with_opacity_row(root):
    import copy
    root=copy.deepcopy(root)
    indices=[i for i,row in enumerate(root['items']) if row.get('key')=='backgroundColor']
    if len(indices)!=1 or any(row.get('key')=='backgroundTransparency' for row in root['items']):
        raise AssertionError('opacity row must be unique and follow the background picker')
    root['items'].insert(indices[0]+1,dict(ROW))
    return root
