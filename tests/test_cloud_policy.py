"""Cloud-only RootHide build policy, parsed as JSON (valid YAML)."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CloudBuildPolicyTests(unittest.TestCase):
    def test_single_candidate_push_selects_only_roothide_on_mac(self):
        path = ROOT / ".github/workflows/roothide.yml"
        self.assertTrue(path.is_file(), "missing bounded cloud workflow")
        workflow = json.loads(path.read_text())
        self.assertEqual(workflow["on"], {"push": {"branches": ["candidate/roothide-readiness"]}})
        self.assertEqual(workflow["permissions"], {"contents": "read"})
        self.assertEqual(set(workflow["jobs"]), {"build"})
        job = workflow["jobs"]["build"]
        self.assertEqual(job["runs-on"], "macos-15")
        self.assertEqual(job["env"]["THEOS_PACKAGE_SCHEME"], "roothide")
        self.assertEqual(job["env"]["THEOS_COMMIT"], "3ac89c984ec652fd16bcd91b33ae16de45ce76fa")
        self.assertIn("Xcode_16.4.app", job["env"]["DEVELOPER_DIR"])
        steps = job["steps"]
        upload = steps[-1]
        self.assertEqual(upload["if"], "always()")
        self.assertIn("upload-artifact@", upload["uses"])
        runs = "\n".join(step.get("run", "") for step in steps)
        self.assertIn("make -C reconstructed", runs)
        self.assertIn("SYSROOT=", runs)
        self.assertIn("verify_package.py", runs)
        self.assertIn("GLINT_RUNTIME_HOST_PASS", runs)
        self.assertNotIn("workflow_dispatch", runs)
        self.assertNotIn("gh release", runs)
        self.assertNotIn("simctl", runs)

    def test_counter_replay_compiles_actual_production_implementation(self):
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        runs = "\n".join(step.get("run", "") for step in workflow["jobs"]["build"]["steps"])
        self.assertIn("reconstructed/Sources/GLTUnlocks.m", runs)
        self.assertIn("GLINT_UNLOCKS_HOST_PASS", runs)


if __name__ == "__main__":
    unittest.main()
