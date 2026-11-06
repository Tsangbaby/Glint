"""Original-bound picker source contracts, not UIKit/device execution.

Original arm64 a4f0aabf448ebc50ddfaf8a2e08dcd2262ae494e01ff0756e9ab64bfa0ddc3bb:
row 0x9f7c, cell 0xa4bc, show 0xaa38, tap 0xb2f4, hide 0xb3d8.
Nil preview is intentionally passed through attributedStringWithFont:color:;
the original does not fabricate preview text or remove the catalogue label.
"""
from pathlib import Path
import os
import re
import unittest

ROOT = Path(os.environ.get("GLINT_SOURCE_ROOT", Path(__file__).resolve().parents[1]))
CONTROLLER = ROOT / "reconstructed/Sources/GLTController.m"


def method(name):
    text = CONTROLLER.read_text()
    matches = re.findall(r"^- \([^\n)]+\)" + re.escape(name)
                         + r"(?=\s|:)[^\n]*\{\n.*?^\}", text, re.M | re.S)
    if len(matches) != 1:
        raise AssertionError("non-unique picker method: " + name)
    return matches[0]


def compact(text):
    return re.sub(r"\s+", "", text)


class PickerPreviewContracts(unittest.TestCase):
    def test_row_keeps_inline_title_and_selected_preview(self):
        row = compact(method("pickerRowForPill"))
        for token in (
            "prefs.backgroundColor?:[UIColorcolorWithWhite:0.06alpha:0.85]",
            "if(prefs.pill==pill)", "preview.layer.borderWidth=2;",
            "[UIColorcolorWithWhite:1alpha:0.9].CGColor",
            "ceil(CGRectGetWidth(label.bounds))+28", "preview.frame=CGRectMake(0,0,previewWidth,34)",
            "name.center=CGPointMake(CGRectGetMaxX(preview.frame)+10+CGRectGetWidth(name.bounds)*0.5,17)",
            "row.frame=CGRectMake(0,0,CGRectGetMaxX(name.frame),34)",
            "[UIFontsystemFontOfSize:13weight:UIFontWeightSemibold]",
            "name.layer.shadowOpacity=0.4", "name.layer.shadowRadius=3", "name.layer.shadowOffset=CGSizeZero",
            "row.tag=pill", "@selector(pickerRowTapped:)",
        ):
            self.assertIn(token, row)
        self.assertNotIn("CGRectGetMaxY(bounds)+6", row)

    def test_cell_has_dynamic_preview_above_full_width_title(self):
        cell = compact(method("pickerCellForPill"))
        for token in (
            "prefs.backgroundColor?:[UIColorcolorWithWhite:0.06alpha:0.85]",
            "if(prefs.pill==pill)", "preview.layer.borderWidth=2;",
            "label.minimumScaleFactor=0.7", "name.minimumScaleFactor=0.8",
            "MIN(ceil(CGRectGetWidth(label.bounds)),width-24)",
            "preview.frame=CGRectMake((width-previewWidth-24)*0.5,0,previewWidth+24,34)",
            "label.frame=CGRectMake(12,0,previewWidth,34)",
            "name.frame=CGRectMake(0,38,width,14)", "cell.frame=CGRectMake(0,0,width,52)",
            "name.layer.shadowOpacity=0.4", "name.layer.shadowRadius=3", "name.layer.shadowOffset=CGSizeZero",
            "name.adjustsFontSizeToFitWidth=YES", "name.textAlignment=NSTextAlignmentCenter",
        ):
            self.assertIn(token, cell)

    def test_all_fifteen_options_keep_stable_identity_and_nil_preview_labels(self):
        prefs = (ROOT / "reconstructed/Sources/GLTPrefs.m").read_text()
        order_match = re.search(r"\+ \(NSArray \*\)pillOrder \{(.*?)\n\}", prefs, re.S)
        assert order_match is not None
        order = order_match.group(1)
        private_header = (ROOT / "reconstructed/GlintPrivate.h").read_text()
        identities = re.findall(r"\b(GLTPill\w+)\s*=\s*(\d+)", private_header)
        self.assertEqual([int(value) for _, value in identities], list(range(15)))
        self.assertCountEqual([name for name, _ in identities], re.findall(r"@\((GLTPill\w+)\)", order))
        # Original +pillOrder points to boxed integers, not an enum-ordered list.
        # 0x2f028 -> values 0,1,2,3,11,4,9,5,6,8,12,7,10,13,14.
        self.assertEqual(re.findall(r"@\((GLTPill\w+)\)", order), [
            "GLTPillTime", "GLTPillDate", "GLTPillBattery", "GLTPillNetwork",
            "GLTPillStorage", "GLTPillNowPlaying", "GLTPillNextEvent", "GLTPillCalendar",
            "GLTPillReminders", "GLTPillAlarm", "GLTPillCountdown", "GLTPillWeather",
            "GLTPillSun", "GLTPillUnlocks", "GLTPillQuickMessage"])
        names_match = re.search(r"names = @\[(.*?)\];", prefs, re.S)
        assert names_match is not None
        names = names_match.group(1)
        self.assertEqual(re.findall(r'@"([^"]+)"', names), [
            "Time", "Date", "Battery", "Network Speed", "Now Playing", "Calendar",
            "Reminders", "Weather", "Alarm & Timer", "Next Event", "Sunrise & Sunset",
            "Storage & Memory", "Countdown", "Unlocks", "Quick Message"])
        for name in ("pickerRowForPill", "pickerCellForPill"):
            text = compact(method(name))
            self.assertIn("[selfcontentForPill:pill]", text)
            self.assertIn("[contentattributedStringWithFont:fontcolor:prefs.textColor]", text)
            self.assertIn("name.text=[GLTPrefsnameForPill:pill]", text)
            self.assertNotIn("if(!content)", text)
            self.assertNotIn("label.text=", text)
        self.assertIn('CFPreferencesSetAppValue(CFSTR("pill")', prefs)
        self.assertIn('doubleForKey:@"pill" fallback:0 min:0 max:14', prefs)


class PickerLayoutContracts(unittest.TestCase):
    def test_host_local_adaptive_layout_keeps_every_option(self):
        show = compact(method("showPicker"))
        for token in (
            "_pickerView||_platterView", "[selfcanPresentOverlay]",
            "UIView*host=_window.rootViewController.view",
            "CGRectanchor=[selfframeOfClock:clock]",
            "CGFloatlistTop=CGRectGetMaxY(anchor)+14",
            "CGFloatlistHeight=CGRectGetHeight(host.bounds)-listTop-MAX(host.safeAreaInsets.bottom,12)",
            "CGRectMake(0,listTop,CGRectGetWidth(host.bounds),listHeight)",
            "list.alwaysBounceVertical=NO", "NSArray*order=[GLTPrefspillOrder]",
            "CGFloatcontentHeight=order.count*42-8",
            "contentHeight<=MIN(CGRectGetHeight(list.bounds),CGRectGetHeight(host.bounds)*0.8)",
            "CGFloatrowX=MIN(MAX(CGRectGetMinX(anchor),12),CGRectGetWidth(host.bounds)-CGRectGetWidth(row.bounds)-12)",
            "row.frame=CGRectMake(rowX,i*42,CGRectGetWidth(row.bounds),CGRectGetHeight(row.bounds))",
            "CGFloatcellWidth=MIN((CGRectGetWidth(host.bounds)-32-10)*0.5,190)",
            "CGFloatstartX=(CGRectGetWidth(host.bounds)-cellWidth*2-10)*0.5",
            "cell.frame=CGRectMake(startX+(i%2)*(cellWidth+10),(i/2)*64,CGRectGetWidth(cell.bounds),CGRectGetHeight(cell.bounds))",
            "contentHeight=((order.count+1)/2)*64-12",
            "list.contentSize=CGSizeMake(CGRectGetWidth(list.bounds),contentHeight)",
            "[[GLTClockItemssharedItems]refresh]",
        ):
            self.assertIn(token, show)
        self.assertEqual(show.count("for(NSUIntegeri=0;i<order.count;i++)"), 2)
        self.assertNotIn("mainScreen", show)
        self.assertNotIn("columns=3", show)
        self.assertNotIn("MIN(contentHeight", show)


class PickerInteractionContracts(unittest.TestCase):
    def test_present_animates_from_anchor_and_blur_tap_dismisses(self):
        show = compact(method("showPicker"))
        for token in (
            "initWithStyle:UIImpactFeedbackStyleMedium", "initWithEffect:nil",
            "[bluraddGestureRecognizer:", "@selector(hidePicker)",
            "blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight",
            "CGPointorigin=[listconvertPoint:CGPointMake(CGRectGetMidX(anchor),CGRectGetMidY(anchor))fromView:host]",
            "cell.alpha=0", "CGAffineTransformMakeScale(0.5,0.5)",
            "CGAffineTransformMakeTranslation(origin.x-cell.center.x,origin.y-cell.center.y)",
            "CGAffineTransformConcat(scale,translation)",
            "animateWithDuration:0.5delay:0.025*currentusingSpringWithDamping:0.78initialSpringVelocity:0options:UIViewAnimationOptionAllowUserInteraction",
            "cell.alpha=1", "cell.transform=CGAffineTransformIdentity",
            "animateWithDuration:0.3animations:",
            "blur.effect=[UIBlurEffecteffectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]",
        ):
            self.assertIn(token, show)
        self.assertNotIn("UIControl", show)
        self.assertNotIn("userInteractionEnabled=NO", show)
        self.assertLess(show.index("CGRectanchor="), show.index("_pickerView=[[UIViewalloc]"))

    def test_selection_clears_temporary_overrides_persists_and_refreshes(self):
        tap = compact(method("pickerRowTapped"))
        tokens = ("NSIntegerpill=gesture.view.tag", "[hapticselectionChanged]",
                  "_volumeUntil=nil", "_notificationUntil=nil",
                  "[[GLTPrefssharedPrefs]setPill:pill]", "if([selfwantsWeather])",
                  "[[GLTWeathersharedWeather]refreshForcing:NO]", "[selfhidePicker]", "[selfupdate]")
        positions = [tap.index(token) if token in tap else -1 for token in tokens]
        self.assertNotIn(-1, positions, "missing original selection operation")
        self.assertEqual(positions, sorted(positions))

    def test_dismiss_clears_owner_disables_input_and_removes_after_fade(self):
        hide = compact(method("hidePicker"))
        for token in ("UIView*picker=_pickerView", "if(!picker)return", "_pickerView=nil",
                      "picker.userInteractionEnabled=NO", "animateWithDuration:0.22",
                      "picker.alpha=0", "for(UIView*subviewinpicker.subviews)",
                      "[subviewisKindOfClass:[UIVisualEffectViewclass]]",
                      "((UIVisualEffectView*)subview).effect=nil",
                      "subview.transform=CGAffineTransformMakeScale(0.9,0.9)",
                      "completion:^(BOOLfinished){[pickerremoveFromSuperview]", "[selflayoutTouchView]"):
            self.assertIn(token, hide)
        self.assertLess(hide.index("_pickerView=nil"), hide.index("animateWithDuration:"))
        self.assertNotIn("GLTPickerListclass", hide)


if __name__ == "__main__":
    unittest.main()
