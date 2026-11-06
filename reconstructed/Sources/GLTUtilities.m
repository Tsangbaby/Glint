//
//  GLTUtilities.m
//
//  Shared symbol configuration (original 0xb758). Storage accounting and
//  localized byte formatting live with their retained card/preview consumers.
//

#import "Glint.h"
#import "GlintPrivate.h"


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
