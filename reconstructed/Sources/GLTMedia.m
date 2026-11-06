//
//  GLTMedia.m
//
//  Now-playing reader. Everything MediaRemote lives behind dlopen/dlsym
//  because the framework is private and not linkable at build time; the same
//  applies to SBMediaController, reached through NSClassFromString.
//
//  Recovered from 0x152e4…0x15c60.
//

#import "Glint.h"
#import <dlfcn.h>

typedef void (*GLTMRRegisterFn)(dispatch_queue_t queue);
typedef void (*GLTMRGetInfoFn)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*GLTMRGetPlayingFn)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*GLTMRGetAppFn)(dispatch_queue_t queue, void (^handler)(CFStringRef bundleID));

static NSString *const kGLTNowPlayingTitle    = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const kGLTNowPlayingArtist   = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const kGLTNowPlayingArtwork  = @"kMRMediaRemoteNowPlayingInfoArtworkData";
static NSString *const kGLTNowPlayingDuration = @"kMRMediaRemoteNowPlayingInfoDuration";
static NSString *const kGLTNowPlayingElapsed  = @"kMRMediaRemoteNowPlayingInfoElapsedTime";
static NSString *const kGLTNowPlayingTime     = @"kMRMediaRemoteNowPlayingInfoTimestamp";
static NSString *const kGLTNowPlayingRate     = @"kMRMediaRemoteNowPlayingInfoPlaybackRate";

// Original metadata fallback at 0x156c0..0x156e8; keep the private declaration
// local to this provider rather than changing the shared SpringBoard surface.
@interface SBMediaController (GLTMetadata)
- (NSDictionary *)_nowPlayingInfo;
@end

static BOOL GLTMediaInfoHasTitle(NSDictionary *info) {
    if (![info isKindOfClass:[NSDictionary class]]) return NO;
    id title = info[kGLTNowPlayingTitle];
    return [title isKindOfClass:[NSString class]] && [title length] > 0;
}

static void *GLTMediaRemoteHandle(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    });
    return handle;
}

@implementation GLTMedia

+ (GLTMedia *)sharedMedia {
    static GLTMedia *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [GLTMedia new]; });
    return shared;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _remotePlaying = -1;

    void *handle = GLTMediaRemoteHandle();
    if (handle) {
        GLTMRRegisterFn registerForNotifications =
            (GLTMRRegisterFn)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (registerForNotifications) {
            registerForNotifications(dispatch_get_main_queue());
        }
    }

    NSArray *names = @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                       @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                       @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"];
    for (NSString *name in names) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(mediaDidChange)
                                                     name:name
                                                   object:nil];
    }

    [self mediaDidChange];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - SpringBoard bridge

- (id)controller {
    Class controllerClass = NSClassFromString(@"SBMediaController");
    return [controllerClass respondsToSelector:@selector(sharedInstance)]
        ? [controllerClass sharedInstance]
        : nil;
}

#pragma mark - Refresh

// Publish each refreshed snapshot from its main-queue completion. The remote
// readers are asynchronous: posting at request time leaves observers stale.
- (void)mediaDidChange {
    void *handle = GLTMediaRemoteHandle();
    GLTMRGetInfoFn getInfo = handle
        ? (GLTMRGetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    GLTMRGetPlayingFn getPlaying = handle
        ? (GLTMRGetPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        GLTMedia *strongSelf = weakSelf;
        if (!strongSelf) return;

        void (^publishInfo)(CFDictionaryRef) = ^(CFDictionaryRef info) {
            NSDictionary *snapshot = (__bridge NSDictionary *)info;
            if (!GLTMediaInfoHasTitle(snapshot)) {
                id controller = [strongSelf controller];
                snapshot = [controller respondsToSelector:@selector(_nowPlayingInfo)]
                    ? [controller _nowPlayingInfo] : nil;
            }
            strongSelf->_info = [snapshot isKindOfClass:[NSDictionary class]] ? [snapshot copy] : nil;
            strongSelf->_infoDate = [NSDate date];
            [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                                object:nil];
        };
        if (getInfo) {
            getInfo(dispatch_get_main_queue(), publishInfo);
        } else {
            publishInfo(NULL);
        }

        if (getPlaying) {
            getPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
                strongSelf->_remotePlaying = playing ? 1 : 0;
                [[NSNotificationCenter defaultCenter] postNotificationName:GLTSourcesDidChangeNotification
                                                                    object:nil];
            });
        }
    });
}

#pragma mark - Metadata

- (BOOL)hasMedia {
    return GLTMediaInfoHasTitle(_info);
}

- (BOOL)isPlaying {
    if (_remotePlaying != -1) return _remotePlaying != 0;
    id controller = [self controller];
    if ([controller respondsToSelector:@selector(isPlaying)]) {
        return [controller isPlaying];
    }
    return NO;
}

- (NSString *)title {
    return _info[kGLTNowPlayingTitle];
}

- (NSString *)artist {
    return _info[kGLTNowPlayingArtist];
}

- (UIImage *)artwork {
    NSData *data = _info[kGLTNowPlayingArtwork];
    return [data isKindOfClass:[NSData class]] ? [UIImage imageWithData:data] : nil;
}

- (double)duration {
    return [_info[kGLTNowPlayingDuration] doubleValue];
}

// Elapsed time drifts away from the reported snapshot while the track plays,
// so extrapolate from the timestamp and the playback rate.
- (double)elapsed {
    double elapsed = [_info[kGLTNowPlayingElapsed] doubleValue];
    if (![self isPlaying]) return elapsed;

    NSDate *timestamp = _info[kGLTNowPlayingTime];
    if (![timestamp isKindOfClass:[NSDate class]]) timestamp = _infoDate;
    double rate = [_info[kGLTNowPlayingRate] doubleValue];
    if ([timestamp isKindOfClass:[NSDate class]] && rate > 0) {
        elapsed += -[timestamp timeIntervalSinceNow] * rate;
    }

    double duration = [self duration];
    if (duration > 0 && elapsed > duration) elapsed = duration;
    return MAX(0, elapsed);
}

#pragma mark - Transport

- (void)togglePlayPause {
    id controller = [self controller];
    if ([controller respondsToSelector:@selector(togglePlayPauseForEventSource:)]) {
        [controller togglePlayPauseForEventSource:0];
    }
}

- (void)nextTrack {
    id controller = [self controller];
    if ([controller respondsToSelector:@selector(changeTrack:eventSource:)]) {
        [controller changeTrack:1 eventSource:0];
    }
}

- (void)previousTrack {
    id controller = [self controller];
    if ([controller respondsToSelector:@selector(changeTrack:eventSource:)]) {
        [controller changeTrack:-1 eventSource:0];
    }
}

@end
