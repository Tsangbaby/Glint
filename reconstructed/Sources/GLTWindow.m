//
//  GLTWindow.m
//  GLTWindow + GLTPickerList
//
//  The overlay is a second UIWindow parked at UIWindowLevelStatusBar. It must
//  never swallow touches meant for SpringBoard, so hit testing only lets
//  through what actually belongs to the platter or the picker.
//
//  Recovered from 0x4e14 (GLTWindow) and 0x4f88 (GLTPickerList).
//

#import "Glint.h"

@implementation GLTWindow

// Let touches inside the on-screen keyboard reach the keyboard's own window,
// and drop anything that resolves to the window itself or to its empty root
// view so SpringBoard keeps receiving icons taps.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.acceptsKeyboard && CGRectContainsPoint(self.keyboardFrame, point)) {
        return nil;
    }

    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self) return nil;
    if (hit == self.rootViewController.view) return nil;
    return hit;
}

- (BOOL)canBecomeKeyWindow {
    return YES;
}

// The overlay draws app icons and blurred platters; a secure context would
// blank it out in screenshots and screen recordings.
- (BOOL)_shouldCreateContextAsSecure {
    return NO;
}

@end

@implementation GLTPickerList

// The picker is a scroll view floating above SpringBoard; taps that miss every
// row belong to the icon grid underneath.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

@end
