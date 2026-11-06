//
//  GLTMedia.h
//  Glint (reconstructed interface)
//
//  Recovered from ObjC metadata of Glint.dylib 1.6.3
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>


@interface GLTMedia : NSObject
{
    NSDictionary *                 _info; // 0x08
    NSDate *                       _infoDate; // 0x10
    long long                      _remotePlaying; // 0x18
}

#pragma mark - class methods
+ (GLTMedia *)sharedMedia;

#pragma mark - instance methods
- (instancetype)init;
- (id)controller;
- (void)mediaDidChange;
- (BOOL)hasMedia;
- (BOOL)isPlaying;
- (id)title;
- (id)artist;
- (id)artwork;
- (double)duration;
- (double)elapsed;
- (void)togglePlayPause;
- (void)nextTrack;
- (void)previousTrack;

@end
