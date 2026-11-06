#!/usr/bin/env python3
"""Verify the original RootHide deb without running any package code.

Proves metadata, payload boundaries, resources, device platform/deployment,
architecture and structural code-page signatures. Not device acceptance.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import subprocess
import tarfile
import tempfile

from verify_macho import bounded, u32be, verify_macho

MAX_PAYLOAD = 100 * 1024 * 1024


def payload_files(data):
    assert len(data) <= MAX_PAYLOAD, "oversized payload archive"
    files, seen = {}, set()
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:") as archive:
        members = archive.getmembers()
        assert len(members) <= 2000, "excessive member count"
        assert sum(member.size for member in members) <= MAX_PAYLOAD
        for member in members:
            path = PurePosixPath(member.name)
            assert not path.is_absolute() and ".." not in path.parts
            assert "\\" not in member.name and "\x00" not in member.name
            name = str(path)
            assert name not in seen, ("duplicate archive member", name)
            seen.add(name)
            if member.isdir():
                continue
            assert member.isfile(), ("unexpected link/special member", name)
            stream = archive.extractfile(member)
            assert stream is not None
            raw = stream.read()
            assert len(raw) == member.size
            files[name] = raw
    return files


def device_platforms(raw):
    magic = u32be(raw, 0)
    if magic in (0xCAFEBABE, 0xCAFEBABF):
        width = 20 if magic == 0xCAFEBABE else 32
        entries = []
        for i in range(u32be(raw, 4)):
            fmt = ">iiIII" if width == 20 else ">iiQQII"
            fields = struct.unpack(fmt, bounded(raw, 8 + i * width, width))
            entries.append((fields[2], fields[3]))
    else:
        entries = [(0, len(raw))]
    results = []
    for offset, length in entries:
        blob = bounded(raw, offset, length)
        endian = "<" if blob[:4] == b"\xcf\xfa\xed\xfe" else ">"
        _, _, subtype, _, ncmds, sizeofcmds, _, _ = struct.unpack(endian + "IiiIIIII", bounded(blob, 0, 32))
        cursor, minimum, platform, install_name = 32, None, None, None
        for _ in range(ncmds):
            cmd, size = struct.unpack(endian + "II", bounded(blob, cursor, 8))
            command = bounded(blob, cursor, size)
            if cmd == 0x32:
                platform, minimum = struct.unpack(endian + "II", bounded(command, 8, 8))
            elif cmd == 0x25:
                platform, minimum = 2, struct.unpack(endian + "I", bounded(command, 8, 4))[0]
            elif cmd == 0xD:
                name_offset = struct.unpack(endian + "I", bounded(command, 8, 4))[0]
                install_name = command[name_offset:].split(b"\0", 1)[0].decode()
            cursor += size
        assert cursor == 32 + sizeofcmds
        assert platform == 2 and minimum is not None, "not an iPhoneOS device slice"
        version = (minimum >> 16, (minimum >> 8) & 255, minimum & 255)
        assert (14, 0, 0) <= version <= (15, 4, 1), ("unsupported deployment", version)
        results.append({"architecture": "arm64e" if subtype & 0xFFFFFF == 2 else "arm64",
                        "platform": "iPhoneOS", "minimum_os": list(version), "install_name": install_name})
    return results


def verify_package(package):
    fields = {}
    for key in ("Package", "Version", "Architecture"):
        fields[key] = subprocess.check_output(["dpkg-deb", "-f", str(package), key], text=True).strip()
    assert fields == {"Package": "com.antonym.glint", "Version": "1.6.3-beta1", "Architecture": "iphoneos-arm64e"}, fields
    payload = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(package)])
    files = payload_files(payload)
    assert not any(name.startswith("var/jb/") for name in files), "rootless payload in RootHide package"
    tweak = "Library/MobileSubstrate/DynamicLibraries/Glint.dylib"
    bundle = "Library/PreferenceBundles/GlintPrefs.bundle/"
    executable = bundle + "GlintPrefs"
    required = {tweak, "Library/MobileSubstrate/DynamicLibraries/Glint.plist", executable,
                bundle + "Info.plist", bundle + "Root.plist", bundle + "icon.png",
                bundle + "icon@2x.png", bundle + "icon@3x.png",
                "Library/PreferenceLoader/Preferences/GlintPrefs.plist"}
    assert required <= set(files), ("missing required payload", sorted(required - set(files)))
    filter_info = plistlib.loads(files["Library/MobileSubstrate/DynamicLibraries/Glint.plist"])
    assert filter_info == {"Filter": {"Bundles": ["com.apple.springboard"]}}
    info = plistlib.loads(files[bundle + "Info.plist"])
    assert info["CFBundleExecutable"] == "GlintPrefs"
    assert info["CFBundleShortVersionString"] == "1.6.3"
    assert info["GLTPackageVersion"] == fields["Version"]
    assert info["NSPrincipalClass"] == "GLTRootListController"
    rows = plistlib.loads(files[bundle + "Root.plist"])["items"]
    defaults = {item.get("key"): item.get("default") for item in rows}
    assert not {"countdownDate", "countdownTitle", "deviceConnections"} & set(defaults)
    selection = [item for item in rows if item.get("key") == "pill"]
    assert len(selection) == 1 and selection[0]["validValues"] == [0, 11, 4, 8, 7, 14]
    assert selection[0]["validTitles"] == ["Time", "Storage & Memory", "Now Playing", "Alarm & Timer", "Weather", "Quick Message"]
    for key in ("enabled", "showMediaWhilePlaying", "replaceBanners", "replaceVolumeHUD"):
        assert defaults[key] is False, ("unsafe first-install default", key)
    magics = (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf")
    machos = sorted(name for name, raw in files.items() if raw.startswith(magics))
    assert machos == sorted([tweak, executable]), ("unexpected Mach-O inventory", machos)
    binaries = []
    with tempfile.TemporaryDirectory(prefix="glint-package-check-") as temporary:
        for index, name in enumerate(machos):
            path = Path(temporary) / str(index)
            path.write_bytes(files[name])
            signatures = verify_macho(path)
            platforms = device_platforms(files[name])
            for entry in signatures:
                assert not any("/var/jb/" in value for value in entry["load_dylibs"] + entry["rpaths"])
            if name == tweak:
                expected = "@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/Glint.dylib"
                assert all(entry["install_name"] == expected for entry in platforms), platforms
            binaries.append({"path": name, "sha256": hashlib.sha256(files[name]).hexdigest(),
                             "signatures": signatures, "device_platforms": platforms})
    return {"package": package.name, "bytes": package.stat().st_size,
            "sha256": hashlib.sha256(package.read_bytes()).hexdigest(), "control": fields,
            "file_count": len(files), "payload_files": sorted(files), "binaries": binaries,
            "kind": "functional_verification", "device_tested": False,
            "signature_evidence": "structure_and_code_page_hashes_not_signer_trust"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = verify_package(args.package)
    text = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.report:
        args.report.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    if not __debug__:
        raise SystemExit("Run without -O: assertions are required")
    main()
