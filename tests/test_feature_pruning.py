"""Focused production-source pruning contracts and compiled C-compatible replay.

These checks do not claim Apple-target compilation or UIKit/device acceptance.
"""
import ctypes
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from test_platter_motion import normalize_beta2_controller

ROOT = Path(__file__).resolve().parents[1]
PRODUCT = ROOT / "reconstructed"
RETAINED = {"Time": 0, "NowPlaying": 4, "Weather": 7, "Alarm": 8,
            "Storage": 11, "QuickMessage": 14}
ORDER = [0, 11, 4, 8, 7, 14]
REMOVED = ["Date", "Battery", "Network", "Calendar", "Reminders", "NextEvent",
           "Sun", "Countdown", "Unlocks"]
SCRATCH = Path(os.environ.get("TMPDIR", str(Path.home() / ".hermes/cache/scratch"))) / "glint-feature-pruning"


def source(path, *, beta2=False):
    text = (PRODUCT / path).read_text()
    if beta2:
        if path != "Sources/GLTController.m":
            raise AssertionError("beta2 controller inverse applied to unrelated source")
        text = normalize_beta2_controller(text)
    # Strip comments without destroying strings (URLs/quoted braces are legal).
    token = r'@?"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/'
    return re.sub(token, lambda m: "" if m[0].startswith(("//", "/*")) else m[0],
                  text, flags=re.S)


def method(path, selector, *, beta2=False):
    text = source(path, beta2=beta2)
    pattern = r"^[+-] \([^\n]+?\)" + re.escape(selector) + r"(?=\s|:|\{|$)"
    matches = list(re.finditer(pattern, text, re.M))
    if len(matches) != 1:
        raise AssertionError(f"Expected one production method {selector}: {len(matches)}")
    start = text.index("{", matches[0].end())
    # Tokenize strings so their braces do not affect nesting.
    depth = 0
    for token in re.finditer(r'@?"(?:\\.|[^"\\])*"|[{}]', text[start:]):
        if token[0] == "{":
            depth += 1
        elif token[0] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:start + token.start()]
    raise AssertionError(f"Unclosed production method {selector}")


class CataloguePruningTests(unittest.TestCase):
    def test_catalogue_preserves_only_retained_ids_and_original_relative_order(self):
        private = source("GlintPrivate.h")
        rows = dict((name, int(value)) for name, value in
                    re.findall(r"GLTPill(\w+)\s*=\s*(\d+)", private))
        self.assertEqual(rows, RETAINED)
        names = re.findall(r"@\((GLTPill\w+)\)", method("Sources/GLTPrefs.m", "pillOrder"))
        self.assertEqual([rows[name.removeprefix("GLTPill")] for name in names], ORDER)
        for selector in ("nameForPill", "symbolForPill"):
            body = method("Sources/GLTPrefs.m", selector)
            self.assertEqual(set(re.findall(r"case GLTPill(\w+):", body)), set(RETAINED))
            self.assertIn("default: return nil;", body)
            self.assertNotIn("static NSArray", body)
        body = method("Sources/GLTPrefs.m", "nameForPill")
        for label in ("Time", "Storage & Memory", "Now Playing", "Alarm & Timer", "Weather", "Quick Message"):
            self.assertIn(f'GLTLocalizedString(@"{label}")', body)

    def test_stale_selection_read_falls_back_without_writing_and_setter_rejects(self):
        text = source("Sources/GLTPrefs.m")
        helper = re.search(r"static BOOL GLTIsSupportedPill\(long long pill\)\s*\{(.*?)\n\}", text, re.S)
        self.assertIsNotNone(helper, "production membership validator is missing")
        reload = method("Sources/GLTPrefs.m", "reload")
        self.assertIn('id pill = [self objectForKey:@"pill"]', reload)
        self.assertIn("_pill = GLTIsSupportedPill(candidate) ? candidate : GLTPillTime;", reload)
        for forbidden in ("setPill:", "CFPreferencesSetAppValue", 'doubleForKey:@"pill"'):
            self.assertNotIn(forbidden, reload)
        setter = method("Sources/GLTPrefs.m", "setPill")
        self.assertIn("if (!GLTIsSupportedPill(pill)) return;", setter)
        self.assertLess(setter.index("GLTIsSupportedPill"), setter.index("_pill = pill;"))
        self.assertIn('CFPreferencesSetAppValue(CFSTR("pill")', setter)

    def test_compiled_production_membership_rejects_retired_and_out_of_range_ids(self):
        text = source("Sources/GLTPrefs.m")
        helper = re.search(r"static BOOL GLTIsSupportedPill\(long long pill\)\s*\{.*?\n\}", text, re.S)
        self.assertIsNotNone(helper, "missing production helper, not a host compile error")
        enum = re.search(r"typedef NS_ENUM\(NSInteger, GLTPill\)\s*\{(.*?)\};", source("GlintPrivate.h"), re.S)
        self.assertIsNotNone(enum)
        assert helper is not None and enum is not None
        assignment = re.search(r"_pill = GLTIsSupportedPill\(candidate\).*?;", method("Sources/GLTPrefs.m", "reload"))
        self.assertIsNotNone(assignment)
        assert assignment is not None
        host = ("typedef int BOOL;\n#define YES 1\n#define NO 0\n"
                + "enum GLTPill {" + enum[1] + "};\n" + helper[0]
                + "\nint supported(long long pill) { return GLTIsSupportedPill(pill); }\n"
                + "long long readSelection(long long candidate) { long long _pill; " + assignment[0] + " return _pill; }\n")
        SCRATCH.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
            path = Path(directory)
            (path / "membership.c").write_text(host)
            result = subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-shared", "-fPIC",
                                     str(path / "membership.c"), "-o", str(path / "membership.so")],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            lib = ctypes.CDLL(str(path / "membership.so"))
            lib.supported.argtypes = [ctypes.c_longlong]
            lib.supported.restype = ctypes.c_int
            lib.readSelection.argtypes = [ctypes.c_longlong]
            lib.readSelection.restype = ctypes.c_longlong
            for value in list(range(-32, 65)) + [-(2 ** 63), 2 ** 63 - 1]:
                with self.subTest(pill=value):
                    self.assertEqual(bool(lib.supported(value)), value in RETAINED.values())
                    self.assertEqual(lib.readSelection(value), value if value in RETAINED.values() else 0)


class RuntimePruningTests(unittest.TestCase):
    def test_retired_providers_and_headers_are_deleted_not_just_hidden(self):
        for path in ("Sources/GLTEvents.m", "Sources/GLTUnlocks.m", "Headers/GLTEvents.h",
                     "Headers/GLTUnlocks.h", "Headers/GLTDevice.h", "Headers/GLTRemindersPlatterView.h"):
            with self.subTest(path=path):
                self.assertFalse((PRODUCT / path).exists(), f"retired implementation remains: {path}")

    def test_retired_runtime_routes_state_and_observers_are_absent(self):
        controller = source("Sources/GLTController.m") + source("Headers/GLTController.h")
        for name in REMOVED:
            self.assertNotRegex(controller, r"\bGLTPill" + name + r"\b")
        for token in ("GLTEvents", "GLTUnlocks", "batteryChanged", "batteryContent", "nextEventContent",
                      "countdownContent", "sunContent", "eventsLeftToday", "countContent:", "sampleNetwork",
                      "speed:", "_dateFormatter", "_networkText", "_lastReceived", "_lastSent", "_lastNetworkDate",
                      "checkDevices", "showConnection:", "showsConnection", "_connectionDevice", "_connectionConnected",
                      "_connectionUntil", "_knownDevices", "batteryMonitoringEnabled", "UIDeviceBattery",
                      "getifaddrs", "ifaddrs.h", "net/if.h", "mach/mach.h", "dlfcn.h", "_ticks"):
            with self.subTest(token=token):
                self.assertNotIn(token, controller)
        self.assertNotRegex(controller, r"\bGLTDevice\b")
        self.assertEqual(set(re.findall(r"case GLTPill(\w+):", method("Sources/GLTController.m", "contentForPill"))), set(RETAINED))
        self.assertEqual(set(re.findall(r"case GLTPill(\w+):", method("Sources/GLTController.m", "platterContent"))), set(RETAINED) - {"Time"})

    def test_retired_preference_keys_and_private_factories_are_absent(self):
        prefs = source("Sources/GLTPrefs.m") + source("Headers/GLTPrefs.h")
        for token in ("deviceConnections", "countdownTitle", "countdownDate"):
            self.assertNotIn(token, prefs)
        shared = source("GlintPrivate.h") + source("Glint.h")
        for token in ("GLTMakeEventsPlatter", "GLTMakeRemindersPlatter", "GLTMakeCountdownPlatter",
                      "GLTMakeUnlocksPlatter", "GLTMakeDevicePlatter", "GLTConnectedDevices", "GLTPercentText", "GLTStorageSummary",
                      "kGLTUnlocksDomain", "GLTRemindersPlatterView", "GLTEvents.h", "GLTUnlocks.h", "GLTDevice.h"):
            self.assertNotIn(token, shared)
        for name in ("Media", "Weather", "Clock", "Storage", "Compose", "Notification"):
            self.assertIn("GLTMake" + name + "Platter", shared)
        self.assertIn('#import "GLTLocalization.h"', shared)
        self.assertNotIn("EventKit", shared)
        self.assertNotIn("EventKit", source("Makefile"))

    def test_only_battery_section_is_removed_from_models(self):
        import hashlib
        text = source("Sources/GLTModels.m")
        for token in ("BCBatteryDevice", "BatteryCenter.framework", "GLTConnectedDevices", "GLTDevice",
                      "GLTGlyphForDeviceName", "GLTDetailsForParts", "batteryLevel", "batteryState"):
            self.assertNotIn(token, text)
        # Everything from Alarm onward is the accepted baseline, including send guards.
        tail = (PRODUCT / "Sources/GLTModels.m").read_bytes().split(b"#pragma mark - Alarm", 1)[1]
        # Parent completes Chinese recipient-type labels only; all remaining
        # models, lookup logic, persistence and send guards stay byte-identical.
        tail = re.sub(rb'GLTLocalizedString\((@"(?:\\.|[^"\\])*")\)', rb'\1', tail)
        self.assertEqual(hashlib.sha256(tail).hexdigest(), "b1439de03e9beae1a36b08191cfba4d2bc3f39ad21927dcb2263f7ada162ee29")

    def test_retained_shell_picker_and_native_date_companion_are_unchanged(self):
        import hashlib
        expected = {
            "registerClockView": "a7cd351f4675fbae6867da557d6ad80b7acb4170340f67ccb3b09350f9e2cb5f",
            "renderClocks": "a508c93032e64d52ec1aaff40941fe290fd645f0be186185f10d69e27f30bb17",
            "layoutTouchView": "2f3e5fa70c9c0e3664f5f9bacc9c14883868a78c5701dfb94e88876d241724f1",
            "openPlatter": "f2e114452f09812e10e80e8d60f3745ea0da3ae7d51626769880aa660003e8db",
            "closePlatterAnimated": "938253ad9dd4de2e2d6d9ef8246628990e52a7ad5ca134111cb7de1663662cc8",
            "fitPlatterToContent": "17278ec3ebdc1c592910b47bec0139f281ba3483e21a209e19e7fdc1bcb59d71",
            "clockTapped": "efd8df814438b481ddf14d752109072b0526e9e3320cdba61d9154ee7b52ea47",
            "pickerRowForPill": "c37f93109cae9d1f95aa4308d13b01685c93109dfff209b35aff3888bd6715d3",
            "pickerCellForPill": "ed82fc0718a5bf2f2ff669403cebc7a4225daae9391b321223dafdb47ec1f8e6",
            "showPicker": "d48bccdfa6ff8c8e4e9de8b5b1d5c7287b680d80b4f9fc7fa44c96c9091ccb59",
            "hidePicker": "84bb74303f136e9497dad6fd78e9b27e601d1f4f5ad098afa11a9a4ccd56aea7",
        }
        for selector, digest in expected.items():
            with self.subTest(selector=selector):
                self.assertEqual(hashlib.sha256(method("Sources/GLTController.m", selector, beta2=True).encode()).hexdigest(), digest)
        text = source("Sources/GLTController.m")
        self.assertIn("_dateViews", text)
        self.assertIn("_timeFormatter", text)
        self.assertIn("GLTDeviceIsLocked()", text)
        self.assertIn("GLTStatusBarHooksReady()", text)
        self.assertIn("return prefs.pill == GLTPillWeather;", method("Sources/GLTController.m", "wantsWeather"))
        for factory in ("Media", "Weather", "Clock", "Storage", "Compose", "Notification"):
            self.assertIn("GLTMake" + factory + "Platter", method("Sources/GLTController.m", "platterContent"))

    def test_remaining_controller_user_text_uses_localization_helper(self):
        for selector, labels in (("pillContent", ["Off"]), ("contentForPill", ["Message"]),
                                 ("mediaContent", ["Not Playing"]), ("alarmContent", ["No alarms"])):
            body = method("Sources/GLTController.m", selector)
            for label in labels:
                self.assertIn(f'GLTLocalizedString(@"{label}")', body)


if __name__ == "__main__":
    unittest.main()
