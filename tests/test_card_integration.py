"""Original-bound card/provider integration source contracts, not UIKit execution.

Retained arm64 SHA256 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb.
Card routing 0x8fa8 / jump table 0x27f4f; MobileTimer init 0x17654,
worker 0x177f0 and main-queue snapshot publication 0x17e64.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "reconstructed/Sources"


def method(text, name):
    matches = re.findall(r"^- \([^\n)]+\)" + re.escape(name)
                         + r"(?=\s|:)[^\n]*\{\n.*?^\}", text, re.M | re.S)
    if len(matches) != 1:
        raise AssertionError("missing/duplicate production method: " + name)
    return matches[0]


def compact(text):
    return re.sub(r"\s+", "", text)


class CardIntegrationTests(unittest.TestCase):
    def test_authorized_routes_only_keep_original_retained_cards(self):
        routes = compact(method((SOURCES / "GLTController.m").read_text(), "platterContent"))
        for fragment in (
            "caseGLTPillWeather:", "[[GLTWeathersharedWeather]refreshForcing:NO];",
            "GLTMakeWeatherPlatter()", "caseGLTPillAlarm:[[GLTClockItemssharedItems]refresh];returnGLTMakeClockPlatter();",
            "caseGLTPillNowPlaying:returnGLTMakeMediaPlatter();",
            "caseGLTPillStorage:returnGLTMakeStoragePlatter();",
            "caseGLTPillQuickMessage:returnGLTMakeComposePlatter();",
        ):
            self.assertIn(fragment, routes)
        self.assertNotIn("caseGLTPillTime:", routes)
        for obsolete in ("GLTPillDate", "GLTPillBattery", "GLTPillNetwork", "GLTPillNextEvent",
                         "GLTPillCalendar", "GLTPillReminders", "GLTPillCountdown", "GLTPillSun", "GLTPillUnlocks"):
            self.assertNotIn(obsolete, routes)
        self.assertIn("if([selfshowsVolume])returnnil;", routes)
        self.assertIn("if([selfshowsNotification])returnGLTMakeNotificationPlatter(_notification);", routes)

    def test_clock_uses_original_manager_ownership_and_actual_timer_states(self):
        text = (SOURCES / "GLTClockItems.m").read_text()
        self.assertRegex(text, r"MTTimerStateRunning\s*=\s*3")
        self.assertRegex(text, r"MTTimerStatePaused\s*=\s*2")
        init = compact(method(text, "init"))
        self.assertIn("_alarmManager=[alarmClassnew];", init)
        self.assertIn("_timerManager=[timerClassnew];", init)
        self.assertNotIn("sharedManager", init)
        refresh = compact(method(text, "refresh"))
        for fragment in (
            "[self->_timerManagerrespondsToSelector:@selector(timersSync)]",
            "[timersaddObjectsFromArray:[self->_timerManagertimersSync]?:@[]]",
            "[self->_timerManagerrespondsToSelector:@selector(getCurrentTimerSync)]",
            "MTTimer*runningTimer=nil", "MTTimer*pausedTimer=nil",
            "state==MTTimerStateRunning", "state==MTTimerStatePaused",
            "[candidateFireDatecompare:runningTimer.fireDate]==NSOrderedAscending",
            "fireDate=runningTimer.fireDate;",
            "remaining=runningTimer?0:pausedTimer.remainingTime;",
            "MTTimer*selectedTimer=runningTimer?:pausedTimer;",
            "self->_pausedTimerRemaining!=remaining",
            "self->_pausedTimerRemaining=remaining;", "self->_timerDuration=duration;",
        ):
            self.assertIn(fragment, refresh)
        self.assertNotIn("dateWithTimeIntervalSinceNow:remaining", refresh,
                         "a paused timer must not masquerade as a running fire date")
        self.assertLess(refresh.index("dispatch_async(_queue"), refresh.index("timersSync"))
        publish = refresh.index("dispatch_async(dispatch_get_main_queue()")
        for field in ("_timerFireDate=fireDate", "_pausedTimerRemaining=remaining", "_timerDuration=duration"):
            self.assertGreater(refresh.index(field), publish)

    def test_read_only_recent_recipients_are_typed_and_wired_without_enabling_writes(self):
        # _GLTRecentRecipients 0x18f08 validates array/dictionary/address,
        # reconstructing GLTRecipient via 0x18e6c. The card consumes it at
        # init 0x13980, empty search 0x143a8 and clear 0x145f8.
        models = (SOURCES / "GLTModels.m").read_text()
        recent = models.split("#pragma mark - Recent recipients", 1)[1].split("#pragma mark - iMessage", 1)[0]
        signature = "NSArray<GLTRecipient *> *GLTRecentRecipientSuggestions(void)"
        self.assertIn(signature, recent)
        adapter = recent.split(signature, 1)[1].split("#if !GLINT_VERIFICATION_BUILD", 1)[0]
        for fragment in ("for (id stored in GLTRecentRecipients())", "isKindOfClass:[NSDictionary class]",
                         'stored[@"address"]', "isKindOfClass:[NSString class]", "[GLTRecipient new]",
                         'stored[@"name"]', 'stored[@"detail"]', "recipient.address = address"):
            self.assertIn(fragment, adapter)
        self.assertNotIn("CFPreferencesSetAppValue", adapter)
        self.assertNotIn("requestAccess", adapter)
        write = recent.split("#if !GLINT_VERIFICATION_BUILD", 1)[1]
        self.assertIn("GLTRememberRecipient(GLTRecipient *recipient)", write)
        self.assertIn("CFPreferencesSetAppValue", write)
        self.assertTrue(write.rstrip().endswith("#endif"))
        header = (ROOT / "reconstructed/GlintPrivate.h").read_text()
        self.assertIn(signature + ";", header)
        compose = (SOURCES / "GLTInteractivePlatters.m").read_text().split("@implementation GLTComposePlatterView", 1)[1]
        self.assertIn("[self showSuggestions:GLTRecentRecipientSuggestions()];", method(compose, "initWithFrame"))
        self.assertIn("text.length ? GLTSearchRecipients(text) : GLTRecentRecipientSuggestions()", method(compose, "searchChanged"))
        self.assertIn("[self showSuggestions:GLTRecentRecipientSuggestions()];", method(compose, "clearRecipient"))
        self.assertIn("[self showSuggestions:@[]];", method(compose, "chooseRecipient"))


if __name__ == "__main__":
    unittest.main()
