#!/usr/bin/env python3
"""Copies the files the Windows app shares with the rest of the repo into app/windows/shared/.

Godot loads only files inside its project folder (app/windows/), and the macOS app's resource
symlinks do not survive a Windows checkout, so the Windows app keeps copies. They are committed,
so the Godot project opens on its own. Run this after changing any source below; --check reports
copies that are missing or stale and exits 1, without writing.

    python tools/sync-windows-assets.py [--check]
"""
import filecmp
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEST = ROOT / "app" / "windows" / "shared"

# (source, destination under shared/); a folder copies the files matching the pattern.
SOURCES = [
    ("assets/kenney/mini-characters", "kenney/mini-characters", "*.glb"),
    ("assets/kenney/mini-characters/Textures", "kenney/mini-characters/Textures", "*.png"),
    ("assets/kenney/mini-characters", "kenney/mini-characters", "License.txt"),
    ("assets/kenney/furniture-kit", "kenney/furniture-kit", "*.glb"),
    ("assets/kenney/furniture-kit", "kenney/furniture-kit", "License.txt"),
    ("assets/icons", "icons", "app-icon-1024.png"),
    ("catalog", "catalog", "*.json"),
    ("app/macos/Sources/AgentTown/Resources/Localization/en.lproj", "strings/en.lproj", "*.strings"),
    ("app/macos/Sources/AgentTown/Resources/Localization/zh-Hant.lproj", "strings/zh-Hant.lproj", "*.strings"),
]


def pairs():
    for src, dst, pattern in SOURCES:
        for f in sorted((ROOT / src).glob(pattern)):
            if f.is_file():
                yield f, DEST / dst / f.name


def main() -> int:
    check = "--check" in sys.argv[1:]
    wanted = set()
    stale = []
    for src, dst in pairs():
        wanted.add(dst)
        if dst.exists() and filecmp.cmp(src, dst, shallow=False):
            continue
        stale.append(dst)
        if not check:
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
    # Copies whose source is gone (Godot's .import files beside them are its own and are kept).
    extra = [p for p in DEST.rglob("*") if p.is_file() and p.suffix != ".import" and p not in wanted]
    for p in extra:
        if not check:
            p.unlink()
            imp = p.with_name(p.name + ".import")
            if imp.exists():
                imp.unlink()
    if check:
        for p in stale:
            print(f"stale or missing: {p.relative_to(ROOT)}")
        for p in extra:
            print(f"no longer in the sources: {p.relative_to(ROOT)}")
        return 1 if stale or extra else 0
    print(f"{len(wanted)} files in {DEST.relative_to(ROOT)}; {len(stale)} copied, {len(extra)} removed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
