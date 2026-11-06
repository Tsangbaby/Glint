//
//  GLTUtilities.m
//
//  The three tiny helpers every other file uses. They exist as C functions in
//  the original too (0x1811c byte formatting, 0xb758 symbol configuration,
//  0x17fc0 storage accounting).
//

#import "Glint.h"
#import "GlintPrivate.h"
#import <mach/mach.h>

#pragma mark - Symbols

UIImage *GLTSymbol(NSString *name, CGFloat pointSize, UIImageSymbolWeight weight) {
    if (!name.length) return nil;

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize weight:weight];
    if (@available(iOS 15.0, *)) {
        configuration = [configuration configurationByApplyingConfiguration:
                         [UIImageSymbolConfiguration configurationPreferringMulticolor]];
    }
    return [UIImage systemImageNamed:name withConfiguration:configuration];
}

#pragma mark - Percent text

NSString *GLTPercentText(long long percent) {
    if (percent < 0) return @"--%";
    return [NSString stringWithFormat:@"%.0f%%", (double)percent];
}

#pragma mark - Storage

// Free/total for the data partition. NSFileManager reports bytes; the card
// wants a short human string, so both halves go through NSByteCountFormatter.
NSString *GLTStorageSummary(void) {
    NSDictionary *attributes =
        [[NSFileManager defaultManager] attributesOfFileSystemForPath:@"/private/var" error:nil];

    long long free  = [attributes[NSFileSystemFreeSize] longLongValue];
    long long total = [attributes[NSFileSystemSize] longLongValue];
    if (total <= 0) return @"-";

    NSByteCountFormatter *formatter = [NSByteCountFormatter new];
    formatter.countStyle = NSByteCountFormatterCountStyleFile;

    return [NSString stringWithFormat:@"%@ free of %@",
            [formatter stringFromByteCount:free],
            [formatter stringFromByteCount:total]];
}
