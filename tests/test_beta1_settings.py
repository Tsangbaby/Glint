"""Authorized beta1 Settings/version pruning; no iOS UI execution implied."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "c4c7817f66a13b8e76677d2e000112cd8bbe7ae5"
VERSION = "1.6.3-beta1"
KEEP_IDS = [0, 11, 4, 8, 7, 14]
KEEP_NAMES = ["Time", "Storage & Memory", "Now Playing", "Alarm & Timer", "Weather", "Quick Message"]
WEATHER_FOOTER = "Leave empty to use an already-authorized location; otherwise enter a city. Open-Meteo receives the approximate coordinates (about 1 km) of the location or city."


def old_bytes(relative):
    return subprocess.check_output(["git", "show", BASELINE + ":" + relative], cwd=ROOT)


def expected_root():
    original = plistlib.loads(old_bytes("reconstructed/prefs/Resources/Root.plist"))
    kept = []
    removed_section = False
    for row in original["items"]:
        if row.get("cell") == "PSGroupCell":
            removed_section = row.get("label") in ("Countdown", "Devices")
        if removed_section:
            continue
        row = dict(row)
        if row.get("key") == "pill":
            row["validValues"], row["validTitles"] = KEEP_IDS, KEEP_NAMES
        if row.get("cell") == "PSGroupCell" and row.get("label") == "Weather":
            row["footerText"] = WEATHER_FOOTER
        kept.append(row)
    return dict(original, items=kept)


class BetaSettingsTests(unittest.TestCase):
    def test_remove_only_authorized_settings_preserving_remaining_schema(self):
        path = ROOT / "reconstructed/prefs/Resources/Root.plist"
        self.assertEqual(plistlib.loads(path.read_bytes()), expected_root())
        rows = plistlib.loads(path.read_bytes())["items"]
        self.assertFalse({"countdownTitle", "countdownDate", "deviceConnections"} & {r.get("key") for r in rows})
        selection = [r for r in rows if r.get("key") == "pill"]
        self.assertEqual(len(selection), 1)
        self.assertEqual(selection[0]["validValues"], KEEP_IDS)
        self.assertEqual(selection[0]["validTitles"], KEEP_NAMES)

    def test_removed_date_cell_is_gone_and_slider_color_cells_are_byte_preserved(self):
        path = "reconstructed/prefs/GLTCells.m"
        actual = (ROOT / path).read_text()
        prior = old_bytes(path).decode().split("#pragma mark - Date", 1)[0]
        self.assertNotIn("GLTDateCell", actual)
        self.assertNotIn("UIDatePicker", actual)
        # Remove only the initial descriptive comments for an exact body comparison.
        self.assertEqual(actual.split("#import <Preferences/PSTableCell.h>", 1)[1].rstrip(),
                         prior.split("#import <Preferences/PSTableCell.h>", 1)[1].rstrip())

    def test_beta_package_and_settings_banner_versions(self):
        make = (ROOT / "reconstructed/Makefile").read_text()
        control = (ROOT / "reconstructed/control").read_text()
        self.assertRegex(make, r"(?m)^export PACKAGE_VERSION = " + re.escape(VERSION) + r"$")
        self.assertRegex(control, r"(?m)^Version: " + re.escape(VERSION) + r"$")
        info = plistlib.loads((ROOT / "reconstructed/prefs/Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "1.6.3")
        self.assertEqual(info["GLTPackageVersion"], VERSION)
        banner = (ROOT / "reconstructed/prefs/GLTRootListController.m").read_text()
        self.assertIn('objectForInfoDictionaryKey:@"GLTPackageVersion"', banner)
        self.assertIn('@"Version %@", @"Localizable")', banner)
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        self.assertEqual(workflow["on"], {"push": {"branches": ["candidate/roothide-readiness"]}})
        self.assertEqual(workflow["jobs"]["build"]["env"]["THEOS_PACKAGE_SCHEME"], "roothide")
        commands = "\n".join(step.get("run", "") for step in workflow["jobs"]["build"]["steps"])
        self.assertIn("com.antonym.glint_" + VERSION + "_iphoneos-arm64e.deb", commands)
        self.assertNotIn("com.antonym.glint_1.6.3_iphoneos-arm64e.deb", commands)
        # Removal includes public package metadata, not only a hidden selector.
        match = re.search(r"(?m)^Description: (.*)$", control)
        self.assertIsNotNone(match)
        assert match is not None
        description = match.group(1)
        for obsolete in ("date", "battery", "network", "events", "reminders", "countdown", "sunrise", "unlocks"):
            self.assertNotRegex(description.lower(), r"\b" + obsolete + r"\b")


if __name__ == "__main__":
    unittest.main()
