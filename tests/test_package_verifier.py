"""Archive-boundary negative control, not a synthesized build artifact."""
from pathlib import Path
import importlib.util
import io
import sys
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PackageVerifierTests(unittest.TestCase):
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
