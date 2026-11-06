//
//  GLTPillContent.m
//
//  Value object describing what the pill shows, plus the attributed-string
//  assembly that turns it into what the label actually draws.
//  Recovered from 0xb7d8 (factory), 0xb8c4 (attributed string), 0xbf84
//  (image attachment), 0xc05c (badge), 0xc254 (progress bar).
//

#import "Glint.h"

@implementation GLTPillContent

+ (GLTPillContent *)contentWithSymbol:(NSString *)symbol text:(NSString *)text {
    GLTPillContent *content = [GLTPillContent new];
    if (symbol.length) {
        content.image = GLTSymbol(symbol, 12, UIFontWeightSemibold);
    }
    content.text = text;
    return content;
}

#pragma mark - Attributed string

// NSTextAttachment with the glyph vertically centred on the text's cap height.
static NSAttributedString *GLTGlyphAttachment(UIImage *image, CGFloat width, CGFloat height, UIFont *font) {
    NSTextAttachment *attachment = [NSTextAttachment new];
    attachment.image = image;
    attachment.bounds = CGRectMake(0, round((font.capHeight - height) * 0.5), width, height);
    return [NSAttributedString attributedStringWithAttachment:attachment];
}

// Small red capsule with the count in white, used for the "3 events" style
// pills. Drawn once and attached so it scales with the label like a glyph.
static NSAttributedString *GLTBadgeAttachment(long long badge, UIFont *font, UIColor *textColor) {
    NSString *text = [NSString stringWithFormat:@"%lld", badge];
    UIFont *badgeFont = [UIFont monospacedDigitSystemFontOfSize:font.pointSize * 0.75
                                                         weight:UIFontWeightBold];
    NSDictionary *textAttributes = @{ NSFontAttributeName: badgeFont,
                                      NSForegroundColorAttributeName: [UIColor whiteColor] };
    CGSize textSize = [text sizeWithAttributes:textAttributes];

    CGFloat height = round(font.capHeight);
    CGFloat width = textSize.width + height * 0.55;

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height)
                                                           cornerRadius:height * 0.5];
        [[UIColor systemRedColor] setFill];
        [path fill];
        [text drawAtPoint:CGPointMake((width - textSize.width) * 0.5,
                                      (height - textSize.height) * 0.5)
           withAttributes:textAttributes];
    }];

    return GLTGlyphAttachment(image, width, height, font);
}

// Thin progress track appended after the text (music / timer / storage).
static NSAttributedString *GLTProgressAttachment(double progress, UIFont *font, UIColor *tint) {
    CGFloat height = round(font.capHeight);
    CGFloat width = 4;
    CGFloat radius = width * 0.5;
    double fraction = MAX(0.0, MIN(1.0, progress));

    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        UIBezierPath *track = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, width, height)
                                                           cornerRadius:radius];
        [[tint colorWithAlphaComponent:0.25] setFill];
        [track fill];

        CGFloat filled = height * fraction;
        UIBezierPath *bar = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, height - filled, width, filled)
                                                         cornerRadius:MIN(radius, filled * 0.5)];
        [tint setFill];
        [bar fill];
    }];

    return GLTGlyphAttachment(image, width, height, font);
}

- (NSAttributedString *)attributedStringWithFont:(UIFont *)font color:(UIColor *)color {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:@""];
    NSDictionary *textAttributes = @{ NSFontAttributeName: font,
                                      NSForegroundColorAttributeName: color };

    if (_image) {
        UIImage *glyph = _image;
        if (_imageTint) {
            glyph = [_image imageWithTintColor:_imageTint
                                  renderingMode:UIImageRenderingModeAlwaysOriginal];
        }
        CGFloat height = round(font.capHeight);
        CGFloat width = glyph.size.height > 0 ? glyph.size.width * (height / glyph.size.height) : height;
        [result appendAttributedString:GLTGlyphAttachment(glyph, width, height, font)];
        // gap between glyph and text
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:textAttributes]];
    }

    if (_text.length) {
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:_text
                                                                      attributes:textAttributes]];
    }

    if (_badge > 0) {
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:textAttributes]];
        [result appendAttributedString:GLTBadgeAttachment(_badge, font, color)];
    }

    if (_progress > 0) {
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:@" " attributes:textAttributes]];
        [result appendAttributedString:GLTProgressAttachment(_progress, font, color)];
    }

    return result;
}

@end
