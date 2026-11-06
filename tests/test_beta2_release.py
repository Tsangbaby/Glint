"""Current beta2 release identity; historical beta1 acceptance stays frozen."""
import ast
import json
from pathlib import Path
import unittest

from test_beta1_settings import VERSION

ROOT = Path(__file__).resolve().parents[1]


class Beta2ReleaseTests(unittest.TestCase):
    def test_package_verifier_is_bound_to_the_requested_candidate(self):
        self.assertTrue(VERSION.endswith("-beta2"))
        tree = ast.parse((ROOT / "tools/verify_package.py").read_text())
        expected = []
        for node in ast.walk(tree):
            if not isinstance(node, ast.Assert) or not isinstance(node.test, ast.Compare):
                continue
            if isinstance(node.test.left, ast.Name) and node.test.left.id == "fields":
                self.assertEqual(len(node.test.comparators), 1)
                expected.append(ast.literal_eval(node.test.comparators[0]))
        self.assertEqual(expected, [{"Package": "com.antonym.glint", "Version": VERSION,
                                     "Architecture": "iphoneos-arm64e"}])

    def test_candidate_push_keeps_accepted_lane_and_adds_only_beta2(self):
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        self.assertEqual(workflow["on"], {"push": {"branches": [
            "candidate/roothide-readiness", "candidate/" + VERSION]}})
        self.assertEqual(set(workflow["jobs"]), {"build"})
        self.assertEqual(workflow["jobs"]["build"]["env"]["THEOS_PACKAGE_SCHEME"], "roothide")
        self.assertNotIn("workflow_dispatch", workflow["on"])


if __name__ == "__main__":
    unittest.main()
