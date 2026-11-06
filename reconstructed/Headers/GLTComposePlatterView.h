//
//  GLTComposePlatterView.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

#import "GLTPlatterContent.h"

@interface GLTComposePlatterView : GLTPlatterContent
{
    UITextField *                  _toField; // 0x18
    UIButton *                     _recipientChip; // 0x20
    UIStackView *                  _suggestions; // 0x28
    UITextField *                  _messageField; // 0x30
    UIButton *                     _sendButton; // 0x38
    UILabel *                      _statusLabel; // 0x40
    GLTRecipient *                 _recipient; // 0x48
    BOOL                           _sending; // 0x50
    id /* block */                 _closeHandler; // 0x08
    id /* block */                 _resizeHandler; // 0x10
}

#pragma mark - class methods
#pragma mark - instance methods
- (BOOL)wantsKeyboard;
- (id)initWithFrame:(CGRect)arg1;
- (void)didMoveToWindow;
- (void)resize;
- (void)showSuggestions:(NSString *)arg1;
- (void)searchChanged;
- (void)chooseRecipient:(GLTRecipient *)arg1;
- (void)clearRecipient;
- (void)updateSendButton;
- (BOOL)textFieldShouldReturn:(id)arg1;
- (void)showStatus:(NSString *)arg1;
- (void)send;
- (void)composeWithApple:(BOOL)arg1 text:(NSString *)arg2;
- (void)messageComposeViewController:(MFMessageComposeViewController *)arg1 didFinishWithResult:(NSInteger)arg2;

@end
