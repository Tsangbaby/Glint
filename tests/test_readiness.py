"""Source-bound readiness checks; these are not iOS/device execution."""
from pathlib import Path
import os
import plistlib
import re
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
SOURCE = ROOT / "reconstructed"


def read(relative):
    return (SOURCE / relative).read_text(encoding="utf-8")


class CompileReadinessTests(unittest.TestCase):
    def test_subclasses_do_not_redeclare_inherited_ivars(self):
        classes = {}
        for path in sorted((SOURCE / "Headers").glob("*.h")):
            text = re.sub(r"/\*.*?\*/|//[^\n]*", "", path.read_text(), flags=re.S)
            match = re.search(r"@interface\s+(\w+)\s*:\s*(\w+)\s*\{(.*?)\}", text, re.S)
            if match:
                fields = set(re.findall(r"\b(_\w+)\s*(?:;|\))", match[3]))
                classes[match[1]] = (match[2], fields)
        conflicts = []
        for name, (parent, fields) in classes.items():
            while parent in classes:
                ancestor, inherited = classes[parent]
                conflicts.extend((name, parent, field) for field in sorted(fields & inherited))
                parent = ancestor
        self.assertEqual(conflicts, [], "duplicate inherited instance variables")

    def test_no_handwritten_runtime_destructors(self):
        hits = []
        for path in SOURCE.rglob("*.m"):
            if re.search(r"[-+]\s*\([^)]*\)\s*\.cxx_destruct", path.read_text()):
                hits.append(str(path.relative_to(SOURCE)))
        self.assertEqual(hits, [], "runtime destructor names are not legal source selectors")

    def test_umbrella_declares_platter_before_controller(self):
        prefix = read("GlintPrivate.h")
        self.assertRegex(prefix, r"@class[^;]*\bGLTPlatterView\b[^;]*;")

    def test_picker_never_passes_point_as_rectangle(self):
        self.assertNotRegex(read("Sources/GLTController.m"), r"CGRectGetMid[XY]\(label\.center\)")

    def test_multicolor_uses_the_declared_class_factory(self):
        text = read("Sources/GLTUtilities.m")
        self.assertNotIn("[configuration configurationPreferringMulticolor]", text)
        self.assertIn("[UIImageSymbolConfiguration configurationPreferringMulticolor]", text)

    def test_suggestions_signature_matches_its_array_implementation(self):
        self.assertIn("showSuggestions:(NSArray<GLTRecipient *> *)", read("Headers/GLTComposePlatterView.h"))

    def test_own_render_writes_are_not_swallowed_by_hooks(self):
        text = read("Tweak.xm")
        guarded = re.findall(r"if \(\[GLTClock isStyled:self\] && (!?)\[GLTClock isRendering\]\)", text)
        self.assertEqual(guarded, ["!", "!", "!"], "system writes blocked, own writes forwarded")

    def test_touch_layout_never_reenters_scene_movement(self):
        text = read("Sources/GLTController.m")
        layout = text.split("- (void)layoutTouchView {", 1)[1].split("#pragma mark - Cards", 1)[0]
        self.assertNotIn("[self moveWindowToScene:", layout)

    def test_runtime_and_message_apis_have_explicit_imports(self):
        header = read("GlintPrivate.h")
        self.assertIn("#import <objc/runtime.h>", header)
        self.assertIn("#import <objc/message.h>", header)
        self.assertIn("@interface SBMediaController", header)
        self.assertIn("@interface NCNotificationRequest", header)
        self.assertIn("timeView;", header)

    def test_runtime_admission_has_fail_closed_lock_and_abi_checks(self):
        source = SOURCE / "Sources/GLTRuntime.m"
        self.assertTrue(source.is_file(), "missing runtime admission implementation")
        text = source.read_text()
        for required in ("method_getTypeEncoding", "numberOfArguments", "getArgumentTypeAtIndex", "notify_register_check", "notify_get_state", "return YES;"):
            self.assertIn(required, text)
        header = read("Headers/GLTRuntime.h")
        self.assertIn('extern "C"', header)

    def test_hook_installation_is_admitted_by_real_method_signatures(self):
        text = read("Tweak.xm")
        self.assertIn("GLTMethodMatches(timeItem", text)
        self.assertIn("GLTMethodMatches(stringView", text)
        self.assertIn("GLTSetStatusBarHooksReady(YES)", text)
        for group in ("GLTStartup", "GLTVolume", "GLTNotifications", "GLTMediaHooks"):
            self.assertIn("%group " + group, text)
            self.assertIn("%init(" + group + ")", text)

    def test_overlay_refuses_locked_or_unready_replacement(self):
        text = read("Sources/GLTController.m")
        self.assertIn("- (BOOL)canPresentOverlay", text)
        self.assertIn("GLTDeviceIsLocked()", text)
        self.assertIn("GLTStatusBarHooksReady()", text)
        self.assertIn("GLTLockStateDidChangeNotification", text)
        hooks = read("Tweak.xm")
        self.assertGreaterEqual(hooks.count("canPresentOverlay]"), 2)

    def test_first_device_build_cannot_send_messages_or_modify_reminders(self):
        self.assertIn("-DGLINT_VERIFICATION_BUILD=1", read("Makefile"))
        models = read("Sources/GLTModels.m").split("BOOL GLTSendMessage", 1)[1]
        self.assertIn("#if GLINT_VERIFICATION_BUILD", models)
        self.assertLess(models.index("return NO;"), models.index("IMDaemonController"))
        sending = read("Sources/GLTInteractivePlatters.m").split("- (void)send {", 1)[1]
        self.assertIn("Messaging is disabled in this verification build.", sending)
        reminder = read("Sources/GLTEvents.m").split("- (void)completeReminder:", 1)[1]
        self.assertIn("#if GLINT_VERIFICATION_BUILD", reminder)

    def test_weather_never_rewrites_host_location_authorization(self):
        text = read("Sources/GLTWeather.m")
        self.assertNotIn("setAuthorizationStatusByType", text)
        self.assertNotIn("requestAlwaysAuthorization", text)
        self.assertIn("#if GLINT_VERIFICATION_BUILD", text)

    def test_fresh_install_defaults_are_conservative_and_consistent(self):
        text = read("Sources/GLTPrefs.m")
        items = plistlib.loads((SOURCE / "prefs/Resources/Root.plist").read_bytes())["items"]
        defaults = {item.get("key"): item.get("default") for item in items if isinstance(item, dict)}
        for key in ("enabled", "replaceBanners", "replaceVolumeHUD", "deviceConnections", "showMediaWhilePlaying"):
            self.assertIn('boolForKey:@"' + key + '" fallback:NO', text)
            self.assertIs(defaults[key], False)

    def test_disabled_or_locked_ticks_skip_sampling(self):
        text = read("Sources/GLTController.m").split("- (void)tick {", 1)[1].split("- (BOOL)wantsWeather", 1)[0]
        self.assertIn("!prefs.enabled || GLTDeviceIsLocked()", text)
        self.assertLess(text.index("return;"), text.index("[self sampleNetwork]"))

    def test_optional_device_and_clock_providers_are_lazy(self):
        text = read("Sources/GLTController.m")
        tick = text.split("- (void)tick {", 1)[1].split("- (BOOL)wantsWeather", 1)[0]
        self.assertIn("prefs.deviceConnections || [self currentPill] == GLTPillBattery", tick)
        self.assertIn("[self currentPill] == GLTPillAlarm", tick)
        start = text.split("- (void)start {", 1)[1].split("- (void)dealloc", 1)[0]
        self.assertIn("[GLTPrefs sharedPrefs].enabled && [self currentPill] == GLTPillAlarm", start)

    def test_disabled_notifications_forward_before_reading_private_payload(self):
        text = read("Tweak.xm").split("- (void)postNotificationRequest:", 1)[1].split("%end", 1)[0]
        self.assertLess(text.index("%orig;"), text.index("[request sectionIdentifier]"))
        self.assertIn("GLTMethodMatches([request class]", text)

    def test_repeated_device_and_media_reads_do_not_reopen_frameworks(self):
        media = read("Sources/GLTMedia.m")
        self.assertEqual(media.count("dlopen("), 1)
        self.assertIn("GLTMediaRemoteHandle", media)
        devices = read("Sources/GLTModels.m").split("NSArray<GLTDevice *> *GLTConnectedDevices", 1)[1].split("@implementation GLTDevice", 1)[0]
        self.assertIn("dispatch_once", devices)

    def test_preferences_uses_the_explicit_cloud_link_stub_directory(self):
        self.assertIn("GlintPrefs_LDFLAGS += -F$(THEOS)/lib/iphone", read("prefs/Makefile"))

    def test_every_declared_glint_class_has_a_compiled_implementation(self):
        declared = set()
        for path in (SOURCE / "Headers").glob("*.h"):
            declared.update(re.findall(r"@interface\s+(GLT\w+)\s*:", path.read_text()))
        compiled = "\n".join(path.read_text() for path in (SOURCE / "Sources").glob("*.m"))
        implemented = set(re.findall(r"@implementation\s+(GLT\w+)\b", compiled))
        self.assertEqual(sorted(declared - implemented), [], "missing own class provider")
        self.assertIn("lockStateChanged:(BOOL)", read("Headers/GLTUnlocks.h"))

    def test_native_replacement_needs_an_attached_overlay_scene(self):
        text = read("Sources/GLTController.m")
        guard = text.split("- (BOOL)canPresentOverlay {", 1)[1].split("- (UIView *)visibleClock", 1)[0]
        self.assertIn("_window.windowScene", guard)


if __name__ == "__main__":
    unittest.main()
