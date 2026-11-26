#!/usr/bin/env python3
# Modified for TensorUnlock-Win 1.0.0 on 2026-11-26: English comments and messages. Based on X-WIDE GPU-UNLOCK v3.2.2. See CHANGELOG.md.
# SPDX-License-Identifier: GPL-2.0-only
"""Extract the Booter / GSP boot firmware needed for unlocking from NVIDIA's open-source kernel module source.

Why the firmware is not shipped in the package: those .bin files are NVIDIA copyrighted material and cannot be redistributed.
NVIDIA publishes the firmware as generated C arrays in open-gpu-kernel-modules,
so users extract it themselves from the official source; this is legal and reproducible.

Outputs (ga102 shown as an example):
    booter_load_ga102.bin      BooterLoad record + DMEM image + signature
    gsp_boot_ga102.bin         GSP bootloader image
    gsp_boot_desc_ga102.bin    84-byte bootloader descriptor

Usage:
    # 1) Prepare the source, either option:
    #    a. the .tar.xz directly (the script locates the members itself without unpacking the whole archive)
    python extract-assets.py --source NVIDIA-kernel-module-source-610.43.03.tar.xz --chip ga102 --out out
    #    b. an already unpacked source root directory
    python extract-assets.py --source F:\\gu-src\\NVIDIA-kernel-module-source-610.43.03 --chip ga104 --out out
    # 2) List the chips in this source package
    python extract-assets.py --source <...> --list

Official source download:
    https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-<version>.tar.xz
    or https://github.com/NVIDIA/open-gpu-kernel-modules/releases

Two files are still missing after extraction; the script cannot extract them, so get them from your own driver package:
    gsp_ga10x.bin         GSP firmware image (large, tens of MB)
    v67-<chip>-<driver-version>.bin   V67/PLM patch table
"""
from __future__ import annotations

import argparse
import hashlib
import re
import struct
import sys
import tarfile
import zlib
from pathlib import Path

MAGIC = 0x314C5442
LABELS = ("IMAGE_PROD", "HEADER_PROD", "SIG_PROD", "PATCH_LOC", "PATCH_META", "NUM_SIGS")

# Known GA102 sizes: used to check whether this extraction matches the officially verified one. Other chips have no baseline, so only structural checks apply.


def _array_bytes(text: str, label: str) -> bytes:
    marker = f"BINDATA_LABEL_{label}_data[]"
    if text.count(marker) != 1:
        raise ValueError(f"missing or duplicate label {label}")
    start = text.index(marker)
    window = text[max(0, start - 400):start]
    compression = re.findall(r"COMPRESSION: (YES|NO)", window)
    sizes = re.findall(r"DATA SIZE \(bytes\): (\d+)", window)
    if not compression or not sizes:
        raise ValueError(f"{label} is missing its storage declaration")
    expected = int(sizes[-1])
    compressed = compression[-1] == "YES"
    if not 0 < expected <= 16 * 1024 * 1024:
        raise ValueError("asset exceeds the decompression size limit")
    declaration = re.match(re.escape(marker) + r"\s*=\s*\{([^}]*)\};", text[start:], re.S)
    if not declaration:
        raise ValueError("malformed byte array declaration")
    tokens = declaration[1].strip().rstrip(",").split(",")
    if any(not re.fullmatch(r"\s*0x[0-9a-fA-F]{2}\s*", x) for x in tokens):
        raise ValueError("generated array contains invalid bytes")
    raw = bytes(int(item, 16) for item in tokens)
    if compressed:
        stored = re.findall(r"COMPRESSED SIZE \(bytes\): (\d+)", window)
        if not stored or len(raw) != int(stored[-1]):
            raise ValueError("compressed size mismatch")
        inflater = zlib.decompressobj(-15)
        data = inflater.decompress(raw, expected + 1)
        if not inflater.eof or len(inflater.unused_data) != 8 or inflater.unconsumed_tail:
            raise ValueError("compressed stream is truncated or has trailing data")
        crc, size = struct.unpack("<II", inflater.unused_data)
        if size != expected or crc != zlib.crc32(data):
            raise ValueError("compressed stream checksum/length mismatch")
    else:
        data = raw
    if len(data) != expected:
        raise ValueError(f"{label}: decoded {len(data)} bytes, declared {expected}")
    return data


def build_booter(source_text: str) -> bytes:
    image = _array_bytes(source_text, "IMAGE_PROD")
    header = _array_bytes(source_text, "HEADER_PROD")
    signatures = _array_bytes(source_text, "SIG_PROD")
    patch_loc = _array_bytes(source_text, "PATCH_LOC")
    patch_meta = _array_bytes(source_text, "PATCH_META")
    num_sigs = _array_bytes(source_text, "NUM_SIGS")
    if len(header) != 36 or len(patch_loc) != 4 or len(patch_meta) != 12 or len(num_sigs) != 4:
        raise ValueError("BooterLoad record has the wrong size")
    fields = struct.unpack("<9I", header)
    loc = struct.unpack("<I", patch_loc)[0]
    _fuse, engine, ucode = struct.unpack("<3I", patch_meta)
    count = struct.unpack("<I", num_sigs)[0]
    if not count or len(signatures) != count * 384 or fields[4] != 1 or not ucode:
        raise ValueError("unsupported Booter signature table (possibly non-production firmware)")
    if loc < fields[2] or loc + 384 > fields[2] + fields[3] or fields[2] + fields[3] > len(image):
        raise ValueError("signature patch location is outside DMEM")
    for offset, size in ((fields[0], fields[1]), (fields[2], fields[3]), (fields[5], fields[6])):
        if offset + size > len(image) or offset % 256 or size % 256:
            raise ValueError("invalid Falcon transfer range")
    hdr = struct.pack(
        "<14I",
        fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6],
        fields[7], fields[8], loc, ucode, engine, count, len(signatures),
    )
    prefix = struct.pack("<II", MAGIC, 1) + hdr + struct.pack("<II", len(image), len(signatures))
    return prefix + image + signatures


def build_boot(source_text: str) -> tuple[bytes, bytes]:
    image = _array_bytes(source_text, "UCODE_IMAGE_PROD")
    desc = _array_bytes(source_text, "UCODE_DESC_PROD")
    if len(desc) != 84:
        raise ValueError(f"bootloader descriptor length should be 84, got {len(desc)}")
    fields = struct.unpack("<21I", desc)
    if fields[0] != 5 or fields[14] != 1 or fields[19] != len(image) or fields[20] != 0:
        raise ValueError("unsupported bootloader descriptor")
    for index in (1, 3, 8, 10, 12):
        if not fields[index + 1] or fields[index] + fields[index + 1] > len(image):
            raise ValueError("a range in the descriptor exceeds the image")
    return image, desc


def find_members(tar_path: Path, chip: str) -> dict[str, str]:
    """Read only the two needed generated source files from the .tar.xz (the whole archive is tens of MB; nothing is extracted to disk)."""
    want = {
        f"g_bindata_kgspGetBinArchiveBooterLoadUcode_{chip.upper()}.c": "booter",
        f"g_bindata_kgspGetBinArchiveGspRmBoot_{chip.upper()}.c": "boot",
    }
    found: dict[str, str] = {}
    with tarfile.open(tar_path, mode="r:*") as archive:
        for member in archive:
            base = member.name.split("/")[-1]
            if base in want and "/src/nvidia/generated/" in member.name:
                handle = archive.extractfile(member)
                if handle is None:
                    continue
                found[want[base]] = handle.read().decode("ascii")
    return found


def list_chips(source: Path) -> list[str]:
    pattern = re.compile(r"g_bindata_kgspGetBinArchiveGspRmBoot_([A-Za-z0-9]+)\.c$")
    chips: set[str] = set()
    if source.is_dir():
        for path in source.rglob("g_bindata_kgspGetBinArchiveGspRmBoot_*.c"):
            match = pattern.match(path.name)
            if match:
                chips.add(match.group(1).lower())
    else:
        with tarfile.open(source, mode="r:*") as archive:
            for member in archive:
                match = pattern.match(member.name.split("/")[-1])
                if match and "/src/nvidia/generated/" in member.name:
                    chips.add(match.group(1).lower())
    return sorted(chips)


def load_sources(source: Path, chip: str) -> tuple[str, str]:
    if source.is_dir():
        generated = source / "src/nvidia/generated"
        booter_file = generated / f"g_bindata_kgspGetBinArchiveBooterLoadUcode_{chip.upper()}.c"
        boot_file = generated / f"g_bindata_kgspGetBinArchiveGspRmBoot_{chip.upper()}.c"
        for path in (booter_file, boot_file):
            if not path.is_file():
                raise ValueError(f"{path.name} not found in the source (use --list to see which chips this package supports)")
        return booter_file.read_text(encoding="ascii"), boot_file.read_text(encoding="ascii")
    members = find_members(source, chip)
    if set(members) != {"booter", "boot"}:
        raise ValueError(f"no generated files for {chip} in the source package (use --list to see the available chips)")
    return members["booter"], members["boot"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Extract Booter / GSP boot firmware from NVIDIA open-source kernel module source")
    parser.add_argument("--source", type=Path, required=True, help="source root directory, or NVIDIA-kernel-module-source-*.tar.xz")
    parser.add_argument("--chip", help="chip codename: ga102 / ga104 / ga106 / ga107 / ad102 ...")
    parser.add_argument("--out", type=Path, help="output directory")
    parser.add_argument("--list", action="store_true", help="only list the chips in this source package")
    args = parser.parse_args()

    if not args.source.exists():
        raise ValueError(f"source does not exist: {args.source}")

    if args.list:
        chips = list_chips(args.source)
        print("chips in this source package:" + (", ".join(chips) if chips else "(none found)"))
        return 0

    if not args.chip or not args.out:
        raise ValueError("either use --list to list chips, or give both --chip and --out")

    chip = args.chip.lower()
    booter_text, boot_text = load_sources(args.source, chip)
    booter = build_booter(booter_text)
    image, desc = build_boot(boot_text)

    args.out.mkdir(parents=True, exist_ok=True)
    files = {
        f"booter_load_{chip}.bin": booter,
        f"gsp_boot_{chip}.bin": image,
        f"gsp_boot_desc_{chip}.bin": desc,
    }
    for name, data in files.items():
        (args.out / name).write_bytes(data)
        print(f"wrote {name:28s} {len(data):>9d} B  sha256={hashlib.sha256(data).hexdigest()[:16]}…")

    if chip == "ga102":
        expected = {
            "booter_load_ga102.bin": "61256",
            "gsp_boot_ga102.bin": "24576",
            "gsp_boot_desc_ga102.bin": "84",
        }
        ok = all(len(files[n]) == int(s) for n, s in expected.items())
        print("GA102 size reference:" + ("match (reproduced successfully)" if ok else "mismatch -- do not use these files"))
        if not ok:
            return 2

    print("")
    print("Two files are still missing; this script cannot extract them. Get them from your own driver package:")
    print("  gsp_ga10x.bin                GSP firmware image (tens of MB)")
    print(f"  v67-{chip}-<driver-version>.bin        V67/PLM patch table")
    print("Place them in the same gpu-unlock\\<driver-version>\\ folder, then run")
    print(f"  gpu_unlock.exe real --cold --yes --assets \"{args.out}\"")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, zlib.error, tarfile.TarError) as error:
        sys.exit(f"extraction failed: {error}")
