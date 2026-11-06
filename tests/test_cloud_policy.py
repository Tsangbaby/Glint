"""Cloud-only RootHide build policy, parsed as JSON (valid YAML)."""
import ast
import json
import shlex
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

    def test_removed_counter_is_not_reintroduced_by_host_compile(self):
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        runs = "\n".join(step.get("run", "") for step in workflow["jobs"]["build"]["steps"])
        self.assertNotIn("reconstructed/Sources/GLTUnlocks.m", runs)
        self.assertNotIn("GLINT_UNLOCKS_HOST_PASS", runs)
        self.assertIn("reconstructed/Sources/GLTRuntime.m tests/runtime_host.m", runs)
        self.assertIn("GLINT_RUNTIME_HOST_PASS", runs)
        self.assertNotIn("GLTUnlocks", (ROOT / "tests/runtime_host.m").read_text())

    def test_package_build_collects_independent_errors_without_hiding_failure(self):
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        step = next(item for item in workflow["jobs"]["build"]["steps"]
                    if item["name"] == "Compile sign and retain original RootHide deb")
        commands = [shlex.split(line) for line in step["run"].splitlines()
                    if line.strip().startswith("make ") and " package " in line]
        self.assertEqual(len(commands), 1)
        self.assertIn("-k", commands[0], "collect errors across independent targets in the same authorized build")
        self.assertNotIn("-i", commands[0], "do not ignore compiler errors")
        self.assertIn("set -euo pipefail", step["run"], "make failure must remain a failed workflow")

    def test_every_embedded_python_command_is_valid_python(self):
        workflow = json.loads((ROOT / ".github/workflows/roothide.yml").read_text())
        snippets = []
        errors = []
        for step in workflow["jobs"]["build"]["steps"]:
            tokens = shlex.split(step.get("run", ""), comments=True)
            for index in range(2, len(tokens) - 1):
                if tokens[index-2:index+1] != ["python3", "-B", "-c"]:
                    continue
                snippet = tokens[index + 1]
                snippets.append(snippet)
                try:
                    ast.parse(snippet, filename=step["name"])
                except SyntaxError as error:
                    errors.append((step["name"], error.msg))
        self.assertEqual(errors, [], "shell syntax alone does not validate nested Python")
        self.assertEqual(len(snippets), 3, "all workflow inline Python owners must be checked")


if __name__ == "__main__":
    unittest.main()
