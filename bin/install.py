#!/usr/bin/env python3
"""Arch GRUB theme installation with reversible, file-level ownership."""
from __future__ import annotations

import argparse
import difflib
import fcntl
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[1]
PROFILES = {"720p": (1280, 720), "1080p": (1920, 1080), "1440p": (2560, 1440)}
THEMES = ("eva01", "wunder")
DEFAULTS = "etc/default/grub"
CONFIG = "boot/grub/grub.cfg"
RUNTIME = "boot/grub/themes/evangelion"
HOOK = "etc/grub.d/99_evangelion"
STATE = "var/lib/evangelion-grub/state.json"
BACKUP = "var/lib/evangelion-grub/grub.cfg.previous"
LIBRARY = "usr/local/share/evangelion"
COMMAND = "usr/local/bin/eva"
MANAGER = "var/lib/evangelion-grub/manager.json"
PREVIOUS = "var/lib/evangelion-grub/previous"
BEGIN = "# BEGIN EVANGELION GRUB (managed; use install.sh --uninstall)\n"
# Existing installations recorded the old removal command in their marker.
LEGACY_BEGIN = "# BEGIN EVANGELION GRUB (managed; use uninstall.sh)\n"
END = "# END EVANGELION GRUB\n"


class InstallError(Exception):
    pass


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_path(root: Path, relative: str) -> Path:
    parts = PurePosixPath(relative).parts
    if not parts or relative.startswith("/") or any(p in (".", "..") for p in parts):
        raise InstallError(f"Unsafe relative path: {relative}")
    path = root
    for part in parts:
        path = path / part
        if path.is_symlink():
            raise InstallError(f"Refusing symlink: {path}")
    return path


def read_optional(path: Path) -> bytes | None:
    if path.exists() and not path.is_file():
        raise InstallError(f"Expected a regular file: {path}")
    return path.read_bytes() if path.exists() else None


def load_state(root: Path) -> dict | None:
    data = read_optional(safe_path(root, STATE))
    if data is None:
        return None
    state = json.loads(data)
    if not isinstance(state, dict) or state.get("version") not in (1, 2) or not isinstance(state.get("files"), dict):
        raise InstallError("Unsupported or damaged ownership manifest")
    for relative, value in state["files"].items():
        safe_path(root, relative)
        if (not relative.startswith(RUNTIME + "/") or not isinstance(value, str)
                or not re.fullmatch(r"[a-f0-9]{64}", value)):
            raise InstallError("Unsafe ownership manifest")
    if not isinstance(state.get("block"), str) or not state["block"].startswith((BEGIN, LEGACY_BEGIN)):
        raise InstallError("Invalid managed-block record")
    if not isinstance(state.get("hook_hash"), str) or not re.fullmatch(r"[a-f0-9]{64}", state["hook_hash"]):
        raise InstallError("Invalid loader ownership record")
    if not isinstance(state.get("prior_setting_lines"), list):
        raise InstallError("Invalid prior-settings record")
    validate_choice(root, state)
    if state.get("previous") is not None:
        validate_choice(root, state["previous"])
    return state


def validate_choice(root: Path, choice: dict):
    if (not isinstance(choice, dict) or choice.get("theme") not in THEMES
            or choice.get("profile") not in PROFILES or not isinstance(choice.get("gfxmode"), str)
            or not isinstance(choice.get("files"), dict) or f"{RUNTIME}/theme.txt" not in choice["files"]):
        raise InstallError("Invalid theme-choice record")
    mode_for(choice["profile"], choice["gfxmode"], "")
    for relative, value in choice["files"].items():
        safe_path(root, relative)
        if (not relative.startswith(RUNTIME + "/") or not isinstance(value, str)
                or not re.fullmatch(r"[a-f0-9]{64}", value)):
            raise InstallError("Unsafe theme-choice ownership record")


def load_manager(root: Path) -> dict | None:
    data = read_optional(safe_path(root, MANAGER))
    if data is None:
        return None
    manifest = json.loads(data)
    if not isinstance(manifest, dict) or manifest.get("version") != 1 or not isinstance(manifest.get("files"), dict):
        raise InstallError("Unsupported or damaged manager manifest")
    for relative, value in manifest["files"].items():
        safe_path(root, relative)
        if (relative != COMMAND and not relative.startswith(LIBRARY + "/")
                or not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value)):
            raise InstallError("Unsafe manager ownership manifest")
    return manifest


def owned_changes(root: Path, old: dict[str, str], files: dict[str, bytes],
                  *, removing: bool = False) -> dict[str, bytes | None]:
    changes = {}
    for relative in sorted(old.keys() | files.keys()):
        current = read_optional(safe_path(root, relative))
        if relative in old:
            if current is not None and digest(current) != old[relative]:
                if removing:
                    print(f"Preserving modified file: /{relative}")
                    continue
                raise InstallError(f"Refusing to overwrite a modified owned file: /{relative}")
        elif current is not None:
            raise InstallError(f"Refusing to overwrite an unowned file: /{relative}")
        changes[relative] = files.get(relative)
    return changes


def manager_files(source: Path) -> dict[str, bytes]:
    files = {}
    for relative in ("bin/install.py", "bin/manage.py", "bin/eva", "LICENSE", "NOTICE.md",
                     "docs/licenses/space-mono/OFL.txt", "docs/licenses/jetbrains-mono/OFL.txt"):
        files[f"{LIBRARY}/{relative}"] = safe_path(REPO, relative).read_bytes()
    files[COMMAND] = files[f"{LIBRARY}/bin/eva"]
    ready_count = 0
    for theme in THEMES:
        for profile in PROFILES:
            base = safe_path(source.resolve(), f"{theme}/{profile}")
            if not safe_path(base, "runtime-ready.json").is_file():
                continue
            source_files(source, theme, profile)
            # Keep the exact readiness inputs, including the manifest, so future
            # switches can verify the installed catalog without the checkout.
            for path in sorted(base.rglob("*")):
                if path.is_file():
                    files[f"{LIBRARY}/themes/{theme}/{profile}/{path.relative_to(base).as_posix()}"] = path.read_bytes()
            ready_count += 1
    if not ready_count:
        raise InstallError("No ready theme profiles are available for the manager")
    return files


def plan_manager(args, root: Path, *, removing: bool = False) -> dict[str, bytes | None]:
    manifest = load_manager(root)
    files = {} if removing else manager_files(args.source)
    changes = owned_changes(root, manifest["files"] if manifest else {}, files, removing=removing)
    changes[MANAGER] = None if removing else (json.dumps({
        "version": 1, "files": {p: digest(data) for p, data in files.items()}
    }, indent=2, sort_keys=True) + "\n").encode()
    return changes


def strip_block(defaults: str, state: dict | None) -> str:
    starts, ends = defaults.count(BEGIN) + defaults.count(LEGACY_BEGIN), defaults.count(END)
    if not state:
        if starts or ends:
            raise InstallError("Managed block exists without an ownership manifest")
        return defaults
    if starts != 1 or ends != 1 or state["block"] not in defaults:
        raise InstallError("Managed defaults were edited; restore the recorded block before continuing")
    start = defaults.index(state["block"])
    suffix = defaults[start + len(state["block"]):]
    # A later owner-added setting needs the separator even if the original file
    # lacked a final newline. Remove it only when that cannot join two shell lines.
    if (state.get("added_newline") and start > 0 and defaults[start - 1] == "\n"
            and (not suffix or suffix.startswith("\n"))):
        return defaults[:start - 1] + suffix
    return defaults[:start] + suffix


def mode_for(profile: str, explicit: str | None, defaults: str) -> str:
    width, height = PROFILES[profile]
    mode = explicit
    if mode is None and profile == "1440p":
        matches = re.findall(r'^\s*GRUB_GFXMODE\s*=\s*[\"\']?(\d+x\d+)[\"\']?\s*$', defaults, re.M)
        if matches:
            w, h = map(int, matches[-1].split("x"))
            if w >= width and h >= height:
                mode = matches[-1]
    mode = mode or f"{width}x{height}"
    if not re.fullmatch(r"[1-9][0-9]{2,4}x[1-9][0-9]{2,4}", mode):
        raise InstallError("--gfxmode must be one exact WIDTHxHEIGHT mode, without auto or fallback lists")
    w, h = map(int, mode.split("x"))
    if w < width or h < height:
        raise InstallError(f"{mode} is smaller than the {profile} design ({width}x{height})")
    return mode


def source_files(source: Path, theme: str, profile: str) -> dict[str, bytes]:
    base = safe_path(source.resolve(), f"{theme}/{profile}")
    ready_path = safe_path(base, "runtime-ready.json")
    if not ready_path.is_file():
        raise InstallError(f"Theme is unavailable: {theme}/{profile} has no readiness record; run the build")
    ready = json.loads(ready_path.read_text())
    if (not isinstance(ready, dict) or ready.get("ready") is not True
            or ready.get("theme") != theme or ready.get("profile") != profile):
        raise InstallError(f"Theme is unavailable: {theme}/{profile} is not ready")
    if ready.get("canvas") != list(PROFILES[profile]):
        raise InstallError(f"Theme readiness canvas does not match {profile}")
    expected_hashes = ready.get("sha256")
    if not isinstance(expected_hashes, dict) or not expected_hashes:
        raise InstallError("Theme readiness record has no asset hashes; rebuild the theme")
    for relative, value in expected_hashes.items():
        safe_path(base, relative)
        if not isinstance(value, str) or not re.fullmatch(r"[a-f0-9]{64}", value):
            raise InstallError(f"Invalid readiness hash: {relative}")
    files = {}
    actual_hashes = {}
    for path in sorted(base.rglob("*")):
        if path.is_symlink():
            raise InstallError(f"Source contains a symlink: {path}")
        if not path.is_file():
            continue
        relative = path.relative_to(base).as_posix()
        if relative == "runtime-ready.json":
            continue
        data = path.read_bytes()
        actual_hashes[relative] = digest(data)
        if relative == "theme.txt" or path.suffix == ".png" or (relative.startswith("fonts/") and path.suffix == ".pf2"):
            if not re.fullmatch(r"[a-zA-Z0-9_./-]+", relative):
                raise InstallError(f"Unsupported runtime filename: {relative}")
            files[f"{RUNTIME}/{relative}"] = data
    if expected_hashes != actual_hashes:
        different = sorted(p for p in expected_hashes.keys() | actual_hashes.keys()
                           if expected_hashes.get(p) != actual_hashes.get(p))
        raise InstallError("Runtime files differ from the readiness record; rebuild: " + ", ".join(different))
    if f"{RUNTIME}/theme.txt" not in files or not any(p.endswith(".png") for p in files):
        raise InstallError("Ready theme is missing theme.txt or PNG artwork")
    if not any(p.endswith(".pf2") for p in files):
        raise InstallError("Ready theme has no PF2 fonts in fonts/")
    validate_references({p.removeprefix(RUNTIME + "/"): data for p, data in files.items()})
    return files


def font_name(data: bytes) -> str:
    """Read the embedded PF2 NAME, which GRUB theme font properties use."""
    if not data.startswith(b"FILE\x00\x00\x00\x04PFF2"):
        raise InstallError("Runtime font has an invalid PF2 header")
    offset = 12
    while offset + 8 <= len(data):
        tag = data[offset:offset + 4]
        size = int.from_bytes(data[offset + 4:offset + 8], "big")
        offset += 8
        if tag == b"DATA":
            break
        if size > len(data) - offset:
            raise InstallError("Runtime font has a truncated PF2 section")
        if tag == b"NAME":
            return data[offset:offset + size].rstrip(b"\x00").decode()
        offset += size
    raise InstallError("Runtime font has no PF2 NAME section")


def validate_references(files: dict[str, bytes]):
    """Validate the generated subset of GRUB theme resource and font properties."""
    names = {font_name(data) for path, data in files.items() if path.endswith(".pf2")}
    for path, data in files.items():
        if path.endswith(".png") and not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise InstallError(f"Runtime PNG has an invalid signature: {path}")
    direct = {"desktop-image", "file", "center_bitmap", "tick_bitmap"}
    styles = {"item_pixmap_style", "selected_item_pixmap_style", "menu_pixmap_style",
              "scrollbar_frame", "scrollbar_thumb", "bar_style", "highlight_style"}
    fonts = {"font", "item_font", "selected_item_font", "title-font", "message-font", "terminal-font"}
    properties = re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*[:=]\s*(?:"([^"\r\n]*)"|([^\s#}]+))',
                            files["theme.txt"].decode(), re.M)
    for key, quoted, unquoted in properties:
        value = quoted or unquoted
        if key in direct:
            if value not in files or not value.endswith(".png"):
                raise InstallError(f"Missing or unsupported theme image reference: {key}={value}")
        elif key in styles:
            if not re.fullmatch(r"[A-Za-z0-9_./-]+_\*\.png", value):
                raise InstallError(f"Unsupported styled-box reference: {value}")
            allowed = {value.replace("*", suffix) for suffix in ("c", "n", "s", "e", "w", "nw", "ne", "sw", "se")}
            found = {p for p in files if fnmatch.fnmatchcase(p, value)}
            if value.replace("*", "c") not in found or not found <= allowed:
                raise InstallError(f"Missing center slice or invalid styled-box slices: {value}")
        elif key in fonts and value not in names:
            raise InstallError(f"Theme font is not present in the packaged PF2 files: {value}")


def make_block(mode: str) -> str:
    return (BEGIN + '# The late loader selects the theme only after the exact mode succeeds.\n'
            'GRUB_THEME=""\nGRUB_FONT=""\n' + f'GRUB_GFXMODE="{mode}"\n'
            'GRUB_TIMEOUT_STYLE="menu"\n' + END)


def make_hook(mode: str, files: dict[str, bytes]) -> bytes:
    fonts = sorted(p.removeprefix("boot/grub/") for p in files if p.endswith(".pf2"))
    loads = "".join(f'loadfont "$prefix/{font}"\n' for font in fonts)
    # Deactivate any previous graphics terminal before asking for an exact mode.
    # GRUB 2.14 gfxterm appends ';auto' internally even for an exact gfxmode.
    # The deliberately invalid final token stops parsing before that hidden fallback.
    # Both branches have been boot-tested; see .dev/docs/runtime-evidence.md in the development checkout.
    return ("#!/bin/sh\nexec tail -n +3 \"$0\"\n"
            "# Evangelion exact-mode loader\nterminal_output console\nunset theme\n"
            f"set gfxmode={mode},evangelion_no_auto_fallback\nload_video\ninsmod gfxterm\ninsmod gfxmenu\ninsmod png\n"
            'loadfont "$prefix/fonts/unicode.pf2"\n' + loads +
            "if terminal_output gfxterm; then\n"
            '  set theme="$prefix/themes/evangelion/theme.txt"\n  export theme\n'
            "else\n  unset theme\n  terminal_output console\nfi\n").encode()


class Transaction:
    """Restore changed files on Python exceptions, including generation/check failure."""

    def __init__(self, root: Path):
        self.root = root
        self.saved: dict[str, tuple[bytes | None, int, int, int]] = {}
        self.created_dirs: list[Path] = []

    def remember(self, relative: str) -> Path:
        path = safe_path(self.root, relative)
        if relative not in self.saved:
            data = read_optional(path)
            info = path.stat() if data is not None else None
            self.saved[relative] = (data, stat.S_IMODE(info.st_mode) if info else 0o644,
                                    info.st_uid if info else os.geteuid(), info.st_gid if info else os.getegid())
        return path

    def write(self, relative: str, data: bytes, mode: int | None = None):
        path = self.remember(relative)
        missing = []
        parent = path.parent
        while not parent.exists():
            missing.append(parent)
            parent = parent.parent
        for directory in reversed(missing):
            directory.mkdir(mode=0o755)
            self.created_dirs.append(directory)
        fd, temp = tempfile.mkstemp(prefix=f".{path.name}.evangelion-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
                stream.flush()
                os.fsync(stream.fileno())
                os.fchmod(stream.fileno(), mode if mode is not None else self.saved[relative][1])
                if os.geteuid() == 0:
                    os.fchown(stream.fileno(), self.saved[relative][2], self.saved[relative][3])
            os.replace(temp, path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)

    def remove(self, relative: str):
        path = self.remember(relative)
        if path.exists():
            path.unlink()

    def rollback(self):
        for relative, (data, mode, _, _) in reversed(list(self.saved.items())):
            if data is None:
                path = safe_path(self.root, relative)
                if path.exists():
                    path.unlink()
            else:
                self.write(relative, data, mode)
        for directory in reversed(self.created_dirs):
            try:
                directory.rmdir()
            except OSError:
                pass


def check_system(root: Path):
    # /etc/os-release normally links to ../usr/lib/os-release on Arch. This
    # identity file is read-only, unlike every destination guarded by safe_path.
    release = (root / "etc/os-release").resolve(strict=True)
    if not release.is_relative_to(root):
        raise InstallError("The OS identity symlink points outside the staging root")
    values = dict(re.findall(r'^([A-Z_]+)=[\"\']?([^\"\'\n]*)', release.read_text(), re.M))
    if values.get("ID") != "arch":
        raise InstallError("This installer currently supports Arch Linux (ID=arch) only")


def check_environment(root: Path):
    check_system(root)
    for relative in (DEFAULTS, CONFIG):
        if not safe_path(root, relative).is_file():
            raise InstallError(f"Existing GRUB installation required: /{relative}")
    if not safe_path(root, "etc/grub.d/00_header").is_file():
        raise InstallError("Arch grub-mkconfig header is missing")


def previous_path(relative: str) -> str:
    return f"{PREVIOUS}/{relative.removeprefix(RUNTIME + '/')}"


def prune_unchanged(root: Path, changes: dict[str, bytes | None]) -> dict[str, bytes | None]:
    return {p: data for p, data in changes.items() if read_optional(safe_path(root, p)) != data}


def plan_changes(args, root: Path) -> tuple[dict[str, bytes | None], dict | None]:
    check_system(root)
    if args.action == "setup":
        print("Install the Evangelion command and verified theme catalog.")
        return prune_unchanged(root, plan_manager(args, root)), None
    state = load_state(root)
    changes: dict[str, bytes | None] = {}
    if args.action == "uninstall":
        changes.update(plan_manager(args, root, removing=True))
        if not state:
            if not prune_unchanged(root, changes):
                print("Evangelion is not installed; no changes.")
            return prune_unchanged(root, changes), None
    check_environment(root)
    defaults = safe_path(root, DEFAULTS).read_bytes().decode()
    base = strip_block(defaults, state)
    old_files = state["files"] if state else {}
    old_previous = state.get("previous") if state else None
    old_snapshot = {previous_path(p): value for p, value in old_previous["files"].items()} if old_previous else {}
    hook = read_optional(safe_path(root, HOOK))
    if state and (hook is None or digest(hook) != state["hook_hash"]):
        raise InstallError("The managed loader changed; restore it before continuing")
    if not state and hook is not None:
        raise InstallError(f"Refusing to overwrite an unowned /{HOOK}")
    if args.action in ("install", "rollback"):
        if args.action == "rollback":
            if not old_previous:
                raise InstallError("No previous Evangelion choice is saved; use uninstall to restore the pre-Evangelion appearance")
            theme, profile, mode = (old_previous[k] for k in ("theme", "profile", "gfxmode"))
            files = {}
            for relative, expected in old_previous["files"].items():
                data = read_optional(safe_path(root, previous_path(relative)))
                if data is None or digest(data) != expected:
                    raise InstallError(f"Previous theme snapshot is missing or modified: /{previous_path(relative)}")
                files[relative] = data
            validate_references({p.removeprefix(RUNTIME + "/"): data for p, data in files.items()})
        else:
            if not args.theme or not args.profile:
                raise InstallError("Installation requires --theme and --profile")
            theme, profile = args.theme, args.profile
            files = source_files(args.source, theme, profile)
            mode = mode_for(profile, args.gfxmode, base)
        changes.update(owned_changes(root, old_files, files))
        hashes = {p: digest(data) for p, data in files.items()}
        changed_choice = state and (state["theme"] != theme or state["profile"] != profile
                                   or state["gfxmode"] != mode or old_files != hashes)
        previous = old_previous
        if changed_choice:
            snapshot = {}
            for relative, expected in old_files.items():
                data = read_optional(safe_path(root, relative))
                if data is None or digest(data) != expected:
                    raise InstallError(f"Current theme cannot be saved for rollback: /{relative} is missing or modified")
                snapshot[previous_path(relative)] = data
            changes.update(owned_changes(root, old_snapshot, snapshot))
            previous = {key: state[key] for key in ("theme", "profile", "gfxmode", "files")}
        block = make_block(mode)
        newline = bool(base and not base.endswith("\n"))
        changes[DEFAULTS] = (base + ("\n" if newline else "") + block).encode()
        changes[HOOK] = make_hook(mode, files)
        state = {"version": 2, "theme": theme, "profile": profile, "gfxmode": mode,
                 "block": block, "added_newline": newline, "previous": previous,
                 "files": hashes, "hook_hash": digest(changes[HOOK]),
                 "prior_setting_lines": state["prior_setting_lines"] if state else
                     re.findall(r'^\s*(?:GRUB_THEME|GRUB_FONT|GRUB_GFXMODE|GRUB_TIMEOUT_STYLE)\s*=.*$', base, re.M)}
        changes[STATE] = (json.dumps(state, indent=2, sort_keys=True) + "\n").encode()
        if args.action == "install" and args.install_manager:
            changes.update(plan_manager(args, root))
        print(f"Selected {theme} {profile}, exact graphics mode {mode}.")
    else:
        changes[DEFAULTS] = base.encode()
        changes[HOOK] = None
        changes[STATE] = None
        changes.update(owned_changes(root, old_files, {}, removing=True))
        changes.update(owned_changes(root, old_snapshot, {}, removing=True))
    # Idempotent selections preserve both the previous choice and config backup.
    return prune_unchanged(root, changes), state


def display_plan(root: Path, changes: dict[str, bytes | None]):
    print(f"Target root: {root}")
    for relative, data in changes.items():
        path = safe_path(root, relative)
        if relative in (DEFAULTS, HOOK):
            before = (read_optional(path) or b"").decode().splitlines(keepends=True)
            after = (data or b"").decode().splitlines(keepends=True)
            print("".join(difflib.unified_diff(before, after, fromfile=f"/{relative} (current)",
                                             tofile=f"/{relative} (proposed)")), end="")
        else:
            operation = "remove" if data is None else ("replace" if path.exists() else "create")
            print(f"{operation}: /{relative}" + (f" ({len(data)} bytes, sha256 {digest(data)})" if data is not None else ""))
    if needs_generation(changes):
        print(f"Regenerate and syntax-check /{CONFIG}; retain one prior configuration at /{BACKUP}.")


def needs_generation(changes: dict[str, bytes | None]) -> bool:
    return bool(changes.keys() & {DEFAULTS, HOOK, STATE})


def file_mode(relative: str) -> int | None:
    if relative in (STATE, MANAGER) or relative.startswith(PREVIOUS + "/"):
        return 0o600
    if relative in (HOOK, COMMAND, f"{LIBRARY}/bin/eva"):
        return 0o755
    return None


def remove_empty_owned_dirs(root: Path, changes: dict[str, bytes | None]):
    directories = set()
    for relative, data in changes.items():
        if data is not None:
            continue
        for prefix in (RUNTIME, PREVIOUS, LIBRARY):
            if relative.startswith(prefix + "/"):
                parent = PurePosixPath(relative).parent
                while str(parent).startswith(prefix):
                    directories.add(str(parent))
                    parent = parent.parent
    for relative in sorted(directories, key=len, reverse=True):
        try:
            safe_path(root, relative).rmdir()
        except OSError:
            pass


def apply_changes(args, root: Path, changes: dict[str, bytes | None]):
    if not changes:
        print("Already in the requested state; no changes.")
        return
    if root == Path("/") and os.geteuid() != 0:
        raise InstallError("Host installation requires root; inspect --dry-run before running with sudo")
    regenerate = needs_generation(changes)
    if regenerate:
        if os.statvfs(safe_path(root, CONFIG).parent).f_flag & os.ST_RDONLY:
            raise InstallError("The GRUB destination is read-only; no files were changed")
        checker = shutil.which("grub-script-check")
        if not checker:
            raise InstallError("grub-script-check is required")
        if root != Path("/"):
            if not args.generator:
                raise InstallError("A staging root requires --generator EXECUTABLE; host grub-mkconfig is never run against a stage")
            generator = [str(args.generator.resolve()), str(root)]
        else:
            if args.generator:
                raise InstallError("--generator is available only with a staging --root")
            mkconfig = shutil.which("grub-mkconfig")
            if not mkconfig:
                raise InstallError("grub-mkconfig is required")
            generator = [mkconfig, "-o"]
    transaction = Transaction(root)
    candidate: Path | None = None
    try:
        # Ownership records commit last; every destination shares this transaction.
        for relative, data in changes.items():
            if relative in (STATE, MANAGER):
                continue
            if data is None:
                transaction.remove(relative)
            else:
                transaction.write(relative, data, file_mode(relative))
        if regenerate:
            # Active grub.cfg is untouched until generation and checking succeed.
            fd, candidate_name = tempfile.mkstemp(prefix=".grub.cfg.evangelion-", dir=safe_path(root, CONFIG).parent)
            os.close(fd)
            candidate = Path(candidate_name)
            subprocess.run(generator + [str(candidate)], check=True)
            subprocess.run([checker, str(candidate)], check=True)
            generated = candidate.read_bytes()
            if not generated.strip():
                raise InstallError("Configuration generator produced an empty file")
            expected_loader = (safe_path(root, HOOK).read_bytes().split(b"\n", 2)[2]
                               if args.action in ("install", "rollback") else None)
            if expected_loader is not None and expected_loader not in generated:
                raise InstallError("Generated config omitted or changed the Evangelion loader")
            if args.action == "uninstall" and b'# Evangelion exact-mode loader\n' in generated:
                raise InstallError("Generated config still contains the Evangelion loader")
            transaction.write(BACKUP, safe_path(root, CONFIG).read_bytes(), 0o600)
            transaction.write(CONFIG, generated)
        for relative in (STATE, MANAGER):
            if relative in changes:
                if changes[relative] is None:
                    transaction.remove(relative)
                else:
                    transaction.write(relative, changes[relative], 0o600)
    except BaseException:
        transaction.rollback()
        print("Operation failed; changed files were restored and the previous grub.cfg retained.", file=sys.stderr)
        raise
    finally:
        if candidate is not None:
            candidate.unlink(missing_ok=True)
            Path(str(candidate) + ".new").unlink(missing_ok=True)
    remove_empty_owned_dirs(root, changes)
    print({"setup": "Evangelion manager installed. Run sudo eva choose to select a theme.",
           "install": "Installation complete.", "rollback": "Previous Evangelion choice restored.",
           "uninstall": "Evangelion removed; prior settings restored."}[args.action])


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "install", "uninstall", "rollback", "list"))
    parser.add_argument("--install-manager", action="store_true", help="install the persistent command and catalog with a theme")
    parser.add_argument("--theme", choices=THEMES)
    parser.add_argument("--profile", choices=PROFILES)
    parser.add_argument("--gfxmode", help="one exact firmware mode, at least the profile dimensions")
    parser.add_argument("--root", type=Path, default=Path("/"), help="staging root; default is the live host")
    parser.add_argument("--source", type=Path, default=REPO / "themes", help="generated themes directory")
    parser.add_argument("--dry-run", action="store_true", help="print exact defaults/loader diff without writing or generating config")
    parser.add_argument("--quiet", action="store_true", help="omit the file plan on apply; dry runs always show the plan")
    parser.add_argument("--generator", type=Path, help="staging-only executable invoked as EXECUTABLE ROOT OUTPUT")
    args = parser.parse_args(argv)
    try:
        if args.action == "list":
            for theme in THEMES:
                ready = []
                for profile in PROFILES:
                    try:
                        source_files(args.source, theme, profile)
                        ready.append(profile)
                    except (InstallError, OSError, ValueError):
                        pass
                if ready:
                    print(f"{theme}: {' '.join(ready)}")
            return 0
        root = args.root.resolve(strict=True)
        if args.dry_run:
            changes, _ = plan_changes(args, root)
            display_plan(root, changes)
            print("Dry run only; configuration generation and boot behavior were not tested.")
        else:
            # Setup does not need GRUB defaults. All operations lock the stable /etc inode.
            lock_fd = os.open(safe_path(root, "etc"), os.O_RDONLY | os.O_DIRECTORY)
            try:
                try:
                    fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError as exc:
                    raise InstallError("Another Evangelion operation is running") from exc
                changes, _ = plan_changes(args, root)
                if not args.quiet:
                    display_plan(root, changes)
                apply_changes(args, root, changes)
            finally:
                os.close(lock_fd)
        return 0
    except (InstallError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"eva: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
