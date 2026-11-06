"""Original-bound provider source contracts, not private-framework/device proof.

Original arm64 SHA256 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Media completion publication 0x1562c / 0x1567c; timer worker 0x177f0.
"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "reconstructed/Sources"


def method(text, name):
    matches = re.findall(r"^- \([^\n)]+\)" + re.escape(name)
                         + r"(?=\s|:)[^\n]*\{\n.*?^\}", text, re.M | re.S)
    if len(matches) != 1:
        raise AssertionError("missing/duplicate production method: " + name)
    return matches[0]


def block(text, anchor):
    if text.count(anchor) != 1:
        raise AssertionError("missing/duplicate production block: " + anchor)
    start = text.index("{", text.index(anchor))
    depth = 1
    end = start + 1
    while depth and end < len(text):
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    if depth:
        raise AssertionError("unterminated production block: " + anchor)
    return text[start + 1:end - 1]


def compact(text):
    return re.sub(r"\s+", "", text)


class RetainedProviderContracts(unittest.TestCase):
    def test_each_media_completion_publishes_after_its_snapshot_write(self):
        # Original stores playing at 0x15640 then posts at 0x15668;
        # metadata/date publication 0x15724..0x15748 precedes 0x15774.
        refresh = method((SOURCES / "GLTMedia.m").read_text(), "mediaDidChange")
        info = block(refresh, "^(CFDictionaryRef info)")
        playing = block(refresh, "^(Boolean playing)")
        for callback, write in ((info, "strongSelf->_info ="),
                                (playing, "strongSelf->_remotePlaying =")):
            self.assertIn("postNotificationName:GLTSourcesDidChangeNotification", callback,
                          "asynchronous snapshot writes must publish in their completion")
            self.assertLess(callback.index(write), callback.index("postNotificationName:"))
        self.assertLess(info.index("strongSelf->_infoDate ="), info.index("postNotificationName:"))
        self.assertEqual(refresh.count("postNotificationName:"), 2,
                         "no speculative notification before deferred callbacks complete")
        self.assertNotIn("NSDictionary *previous", refresh)
        self.assertIn("getInfo(dispatch_get_main_queue()", refresh)
        self.assertIn("getPlaying(dispatch_get_main_queue()", refresh)


    def test_alarm_reads_require_original_capabilities_before_invocation(self):
        # Original 0x17844..0x17870 guards alarmsSync, then 0x178ec..0x17914
        # requires both nextFireDate and isEnabled before admitting an alarm.
        refresh = compact(method((SOURCES / "GLTClockItems.m").read_text(), "refresh"))
        self.assertIn("[self->_alarmManagerrespondsToSelector:@selector(alarmsSync)]?"
                      "[self->_alarmManageralarmsSync]:nil", refresh)
        self.assertIn("if(![alarmrespondsToSelector:@selector(isEnabled)]||![alarmisEnabled])continue;",
                      refresh)
        self.assertIn("if(![alarmrespondsToSelector:@selector(nextFireDate)])continue;", refresh)
        self.assertLess(refresh.index("dispatch_async(_queue"), refresh.index("alarmsSync"))
        self.assertIn("if(_refreshing)return;_refreshing=YES;", refresh)
        main = refresh.index("dispatch_async(dispatch_get_main_queue()")
        self.assertGreater(refresh.index("self->_refreshing=NO"), main)
        self.assertLess(refresh.index("self->_refreshing=NO"), refresh.index("postNotificationName:"))


    def test_remote_playback_snapshot_is_authoritative_after_first_callback(self):
        # Original init stores unknown (-1) at 0x15338/0x1533c; 0x15894..
        # 0x158ac returns remote 0/1 before consulting SpringBoard fallback.
        media = (SOURCES / "GLTMedia.m").read_text()
        self.assertIn("_remotePlaying=-1;", compact(method(media, "init")))
        playing = compact(method(media, "isPlaying"))
        self.assertIn("if(_remotePlaying!=-1)return_remotePlaying!=0;", playing)
        self.assertLess(playing.index("_remotePlaying!=-1"), playing.index("[selfcontroller]"))
        self.assertIn("respondsToSelector:@selector(isPlaying)", playing)
        self.assertIn("returnNO;", playing)


    def test_incomplete_or_unavailable_remote_metadata_uses_original_controller_fallback(self):
        # Original 0x156a0 checks a nonempty NSString title, falls back to
        # guarded _nowPlayingInfo at 0x156ac..0x156e8, and validates NSDictionary.
        media = (SOURCES / "GLTMedia.m").read_text()
        refresh = method(media, "mediaDidChange")
        self.assertNotIn("if (!handle) return;", refresh,
                         "SpringBoard metadata fallback must survive absent MediaRemote")
        info = compact(block(refresh, "^(CFDictionaryRef info)"))
        for fragment in ("if(!GLTMediaInfoHasTitle(snapshot))",
                         "respondsToSelector:@selector(_nowPlayingInfo)",
                         "[controller_nowPlayingInfo]",
                         "strongSelf->_info=[snapshotisKindOfClass:[NSDictionaryclass]]?[snapshotcopy]:nil;"):
            self.assertIn(fragment, info)
        self.assertIn("getInfo(dispatch_get_main_queue(),publishInfo);", compact(refresh))
        self.assertIn("else{publishInfo(NULL);}", compact(refresh))
        self.assertIn("returnGLTMediaInfoHasTitle(_info);", compact(method(media, "hasMedia")))
        helper = compact(block(media, "static BOOL GLTMediaInfoHasTitle("))
        self.assertIn("if(![infoisKindOfClass:[NSDictionaryclass]])returnNO;", helper)
        self.assertIn("[titleisKindOfClass:[NSStringclass]]&&[titlelength]>0", helper)


    def test_elapsed_uses_receipt_time_when_remote_timestamp_is_missing(self):
        # Original 0x15a30..0x15a38 chooses _infoDate when the timestamp is nil.
        elapsed = method((SOURCES / "GLTMedia.m").read_text(), "elapsed")
        self.assertIn("if(![timestampisKindOfClass:[NSDateclass]])timestamp=_infoDate;", compact(elapsed))
        self.assertLess(elapsed.index("timestamp = _infoDate"), elapsed.index("timeIntervalSinceNow"))
        self.assertIn("if (![self isPlaying]) return elapsed;", elapsed)
        self.assertIn("rate > 0", elapsed)
        self.assertIn("elapsed += -[timestamp timeIntervalSinceNow] * rate;", elapsed)
        self.assertIn("if (duration > 0 && elapsed > duration) elapsed = duration;", elapsed)


class RetainedProviderFoundationHost(unittest.TestCase):
    @unittest.skipUnless(sys.platform == "darwin", "Apple Foundation host requires macOS; not device proof")
    def test_exact_provider_sources_with_deferred_recording_readers(self):
        # All production statements are compiled unchanged. Only imports and
        # header ivar visibility are adapted for the Foundation-only test host.
        def without_imports(text):
            return re.sub(r"^#import[^\n]*\n", "", text, flags=re.M)

        interfaces = []
        for name in ("GLTMedia", "GLTClockItems"):
            header = (ROOT / "reconstructed/Headers" / (name + ".h")).read_text()
            interface = header[header.index("@interface "):]
            interfaces.append(interface.replace("{\n", "{\n@public\n", 1))
        media = without_imports((SOURCES / "GLTMedia.m").read_text())
        clock = without_imports((SOURCES / "GLTClockItems.m").read_text())
        scratch = Path.home() / ".hermes/cache/scratch"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="glint-providers-", dir=scratch) as folder:
            folder = Path(folder)
            def run(candidate, name, *args):
                source = FOUNDATION_HOST.replace("/* PROVIDER_INTERFACES */", "\n".join(interfaces))
                source = source.replace("/* MEDIA_SOURCE */", candidate).replace("/* CLOCK_SOURCE */", clock)
                path, executable = folder / (name + ".m"), folder / name
                path.write_text(source)
                build = subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks",
                                        "-framework", "Foundation", "-Werror=return-type",
                                        str(path), "-o", str(executable)], capture_output=True, text=True, timeout=60)
                self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
                return subprocess.run([str(executable), *args], capture_output=True, text=True, timeout=15)

            for args in ((), ("no-handle",)):
                result = run(media, "candidate", *args)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            callback = block(method(media, "mediaDidChange"), "^(CFDictionaryRef info)")
            mutant_callback, count = re.subn(
                r"\[\[NSNotificationCenter defaultCenter\] postNotificationName:"
                r"GLTSourcesDidChangeNotification\s+object:nil\];", "", callback)
            self.assertEqual(count, 1, "mutant must remove only metadata-completion publication")
            result = run(media.replace(callback, mutant_callback, 1), "no-metadata-publication")
            self.assertEqual(result.returncode, 41, result.stdout + result.stderr)
            self.assertIn("metadata callback publishes", result.stderr)


FOUNDATION_HOST = r"""
// Exact provider source is inserted below; only framework/service seams are doubled.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#include <stdio.h>
#include <string.h>
static NSString *const GLTSourcesDidChangeNotification = @"ProviderChange";
static NSMutableArray *tasks;
static void (^infoReply)(CFDictionaryRef);
static void (^playingReply)(Boolean);
static BOOL noHandle, noInfo;
static id controller, fallbackInfo;
static NSArray *alarmInputs, *timerInputs;
static id currentTimer;
static void fakeAsync(dispatch_queue_t queue, dispatch_block_t block) {
    [tasks addObject:[block copy]];
}
static void drain(void) {
    while (tasks.count) {
        dispatch_block_t next = tasks[0];
        [tasks removeObjectAtIndex:0];
        next();
    }
}
static void registerReader(dispatch_queue_t queue) {}
static void readInfo(dispatch_queue_t queue, void (^reply)(CFDictionaryRef)) { infoReply = [reply copy]; }
static void readPlaying(dispatch_queue_t queue, void (^reply)(Boolean)) { playingReply = [reply copy]; }
static void *fakeDlopen(const char *path, int flags) { return noHandle ? NULL : (void *)1; }
static void *fakeDlsym(void *handle, const char *symbol) {
    if (!strcmp(symbol, "MRMediaRemoteRegisterForNowPlayingNotifications")) return (void *)registerReader;
    if (!strcmp(symbol, "MRMediaRemoteGetNowPlayingInfo")) return noInfo ? NULL : (void *)readInfo;
    if (!strcmp(symbol, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")) return (void *)readPlaying;
    return NULL;
}
@interface UIImage : NSObject
+ (UIImage *)imageWithData:(NSData *)data;
@end
@implementation UIImage
+ (UIImage *)imageWithData:(NSData *)data { return nil; }
@end
@interface SBMediaController : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isPlaying;
- (void)togglePlayPauseForEventSource:(NSInteger)source;
- (void)changeTrack:(NSInteger)direction eventSource:(NSInteger)source;
@end
@implementation SBMediaController
+ (instancetype)sharedInstance { return controller; }
- (BOOL)isPlaying { return YES; }
- (void)togglePlayPauseForEventSource:(NSInteger)source {}
- (void)changeTrack:(NSInteger)direction eventSource:(NSInteger)source {}
@end
@interface GLTAlarm : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, strong) NSDate *fireDate;
@end
@implementation GLTAlarm
@end
@class MTAlarmManager, MTTimerManager;
/* PROVIDER_INTERFACES */
#define dispatch_async fakeAsync
#define dlopen fakeDlopen
#define dlsym fakeDlsym
/* MEDIA_SOURCE */
/* CLOCK_SOURCE */
@implementation SBMediaController (GLTMetadata)
- (NSDictionary *)_nowPlayingInfo { return fallbackInfo; }
@end
@implementation MTAlarmManager
- (NSArray *)alarmsSync { return alarmInputs; }
@end
@implementation MTTimerManager
- (NSArray *)timersSync { return timerInputs; }
- (MTTimer *)getCurrentTimerSync { return currentTimer; }
@end
@interface TestTimer : NSObject
@property(nonatomic) NSInteger state;
@property(nonatomic) double remainingTime, duration;
@property(nonatomic, strong) NSDate *fireDate;
@end
@implementation TestTimer
@end
@interface TestAlarm : NSObject
@property(nonatomic, getter=isEnabled) BOOL enabled;
@property(nonatomic, strong) NSDate *nextFireDate;
@property(nonatomic, copy) NSString *displayTitle;
@end
@implementation TestAlarm
@end
@interface AlarmWithoutEnabled : NSObject
@property(nonatomic, strong) NSDate *nextFireDate;
@end
@implementation AlarmWithoutEnabled
@end
#define CHECK(value, label) do { if (!(value)) { fprintf(stderr, "%s\n", label); return 41; } } while (0)
int main(int argc, char **argv) { @autoreleasepool {
    noHandle = argc > 1;
    tasks = [NSMutableArray array];
    controller = [SBMediaController new];
    fallbackInfo = @{@"kMRMediaRemoteNowPlayingInfoTitle": @"fallback"};
    __block GLTMedia *media = nil;
    NSMutableArray *posts = [NSMutableArray array];
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:GLTSourcesDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            [posts addObject:@[media.title ?: @"", @(media.isPlaying)]];
        }];
    media = [GLTMedia new];
    CHECK(posts.count == 0, "no notification at request time");
    drain();
    if (noHandle) {
        CHECK([media.title isEqual:@"fallback"] && media.hasMedia, "fallback without framework");
        CHECK(posts.count == 1, "fallback snapshot publication");
        return 0;
    }
    CHECK(posts.count == 0 && infoReply && playingReply, "remote callbacks are deferred");
    NSMutableDictionary *track = [@{@"kMRMediaRemoteNowPlayingInfoTitle": @"track1"} mutableCopy];
    infoReply((__bridge CFDictionaryRef)track);
    CHECK(posts.count == 1 && [posts.lastObject[0] isEqual:@"track1"], "metadata callback publishes");
    track[@"kMRMediaRemoteNowPlayingInfoTitle"] = @"mutated input";
    CHECK([media.title isEqual:@"track1"], "metadata snapshot owns a copy");
    playingReply(false);
    CHECK(posts.count == 2 && ![posts.lastObject[1] boolValue], "remote pause overrides controller");
    [media mediaDidChange]; drain();
    playingReply(true);
    CHECK(posts.count == 3 && [posts.lastObject[1] boolValue], "playing-only callback publishes");
    infoReply((__bridge CFDictionaryRef)@{@"kMRMediaRemoteNowPlayingInfoTitle": @"track2"});
    CHECK(posts.count == 4 && [posts.lastObject[0] isEqual:@"track2"], "reverse completion order");
    infoReply((__bridge CFDictionaryRef)@{});
    CHECK([media.title isEqual:@"fallback"], "empty metadata falls back");
    fallbackInfo = (id)@"invalid metadata";
    infoReply(NULL);
    CHECK(!media.hasMedia && media.title == nil, "invalid fallback clears metadata");
    fallbackInfo = @{@"kMRMediaRemoteNowPlayingInfoTitle": @"symbol fallback"};
    noInfo = YES;
    [media mediaDidChange]; drain();
    CHECK([media.title isEqual:@"symbol fallback"], "missing info symbol falls back");
    media->_info = @{@"kMRMediaRemoteNowPlayingInfoTitle": @"elapsed",
                     @"kMRMediaRemoteNowPlayingInfoElapsedTime": @10,
                     @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @1,
                     @"kMRMediaRemoteNowPlayingInfoDuration": @100};
    media->_infoDate = [NSDate dateWithTimeIntervalSinceNow:-5];
    media->_remotePlaying = 1;
    CHECK(media.elapsed > 14.9 && media.elapsed < 16, "receipt timestamp advances elapsed");
    media->_remotePlaying = 0;
    CHECK(media.elapsed == 10, "paused elapsed stays fixed");
    [[NSNotificationCenter defaultCenter] removeObserver:observer];

    alarmInputs = @[]; timerInputs = @[];
    GLTClockItems *clock = [GLTClockItems new]; drain();
    clock->_alarmManager = (id)[NSObject new];
    clock->_timerManager = (id)[NSObject new];
    [clock refresh]; drain();
    CHECK(!clock->_refreshing && clock.alarms.count == 0, "unsupported managers fail empty");
    clock->_alarmManager = [MTAlarmManager new];
    clock->_timerManager = [MTTimerManager new];
    NSDate *earlyDate = [NSDate dateWithTimeIntervalSinceNow:60];
    NSDate *lateDate = [NSDate dateWithTimeIntervalSinceNow:120];
    TestTimer *late = [TestTimer new]; late.state = 3; late.fireDate = lateDate; late.duration = 200;
    TestTimer *early = [TestTimer new]; early.state = 3; early.fireDate = earlyDate; early.duration = 100;
    TestTimer *paused = [TestTimer new]; paused.state = 2; paused.remainingTime = 30; paused.duration = 50;
    TestTimer *paused2 = [TestTimer new]; paused2.state = 2; paused2.remainingTime = 20;
    timerInputs = @[late, paused, paused2, [NSObject new]]; currentTimer = early;
    TestAlarm *enabled = [TestAlarm new]; enabled.enabled = YES; enabled.nextFireDate = earlyDate;
    TestAlarm *disabled = [TestAlarm new]; disabled.nextFireDate = lateDate;
    AlarmWithoutEnabled *unknown = [AlarmWithoutEnabled new]; unknown.nextFireDate = lateDate;
    alarmInputs = @[disabled, unknown, enabled];
    [clock refresh]; [clock refresh];
    CHECK(tasks.count == 1, "refresh is single flight");
    drain();
    CHECK([clock.timerFireDate isEqual:earlyDate] && clock.timerDuration == 100,
          "earliest running timer includes current API");
    CHECK(clock.pausedTimerRemaining == 0 && clock.alarms.count == 1,
          "running precedence and enabled alarm capability");
    timerInputs = @[paused, paused2]; currentTimer = nil;
    [clock refresh]; drain();
    CHECK(clock.timerFireDate == nil && clock.pausedTimerRemaining == 30 && clock.timerDuration == 50,
          "first paused timer is not a synthetic running timer");
    timerInputs = @[]; alarmInputs = @[];
    [clock refresh]; drain();
    CHECK(clock.timerFireDate == nil && clock.pausedTimerRemaining == 0 && clock.timerDuration == 0,
          "empty timer snapshot clears fields");
    return 0;
} }
"""


if __name__ == "__main__":
    unittest.main()
