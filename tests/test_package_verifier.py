"""Archive-boundary negative control, not a synthesized build artifact."""
from pathlib import Path
import importlib.util
import collections
import re
import io
import sys
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PackageVerifierTests(unittest.TestCase):
    def test_control_does_not_duplicate_theos_generated_installed_size(self):
        source = (ROOT / "reconstructed/control").read_text()
        # The pinned Theos deb.mk appends this derived field unconditionally.
        generated = source.rstrip() + "\nInstalled-Size: 0\n"
        keys = re.findall(r"^([A-Za-z][A-Za-z0-9-]*):", generated, re.M)
        counts = collections.Counter(key.lower() for key in keys)
        self.assertEqual({key: count for key, count in counts.items() if count > 1}, {})
        self.assertEqual(counts["installed-size"], 1)
        self.assertNotRegex(source, r"(?im)^Installed-Size:")

    def test_payload_parser_rejects_escaping_archive_members(self):
        script = ROOT / "tools/verify_package.py"
        self.assertTrue(script.is_file(), "missing independent package verifier")
        sys.path.insert(0, str(script.parent))
        try:
            spec = importlib.util.spec_from_file_location("glint_package_verifier", script)
            assert spec is not None and spec.loader is not None
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
        finally:
            sys.path.pop(0)
        stream = io.BytesIO()
        with tarfile.open(fileobj=stream, mode="w") as archive:
            member = tarfile.TarInfo("../escape")
            member.size = 1
            archive.addfile(member, io.BytesIO(b"x"))
        with self.assertRaises(AssertionError):
            module.payload_files(stream.getvalue())


if __name__ == "__main__":
    unittest.main()
