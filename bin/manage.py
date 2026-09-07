#!/usr/bin/env python3
"""Choose and switch Evangelion GRUB themes from a terminal."""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.dont_write_bytecode = True
import install as backend

ROOT = Path(__file__).resolve().parents[1]
NAMES = {"eva01": "EVA-01", "wunder": "Wunder", "eva02": "EVA-02"}
PROFILE_NAMES = {"720p": "1280×720", "1080p": "1920×1080", "1440p": "2560×1440 and larger"}


def theme_id(value):
    normalized = value.lower().replace("-", "")
    if normalized not in NAMES:
        raise backend.InstallError(f"Unknown theme: {value}. Use 'eva list' to see available themes.")
    return normalized


def profile_id(value):
    normalized = value.lower().removesuffix("p") + "p"
    if normalized not in backend.PROFILES:
        raise backend.InstallError(f"Unknown profile: {value}. Choose 720p, 1080p or 1440p.")
    return normalized


def catalog(source):
    available = {}
    for theme in NAMES:
        profiles = []
        for profile in backend.PROFILES:
            try:
                backend.source_files(source, theme, profile)
                profiles.append(profile)
            except (backend.InstallError, OSError, ValueError):
                continue
        if profiles:
            available[theme] = profiles
    return available


def prompt_choice(label, values, labels, default):
    print(f"\nChoose a {label.lower()}:")
    for number, value in enumerate(values, 1):
        print(f"  {number}) {labels[value]}")
    default_number = values.index(default) + 1
    while True:
        answer = input(f"{label} [{default_number}]: ").strip()
        if not answer:
            return default
        if answer.isdecimal() and 1 <= int(answer) <= len(values):
            return values[int(answer) - 1]
        for value in values:
            if answer.casefold().replace("-", "") == value.casefold().replace("-", ""):
                return value
        print(f"Choose a number from 1 to {len(values)}.")


def guided(args):
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise backend.InstallError("The chooser needs an interactive terminal. Use 'eva set THEME PROFILE'.")
    available = catalog(args.source)
    if not available:
        raise backend.InstallError("No validated themes are available. Reinstall a complete Evangelion package.")
    state = backend.load_state(args.root)
    themes = list(available)
    current_theme = state.get("theme") if state else None
    default_theme = current_theme if current_theme in themes else themes[0]
    print("Evangelion theme chooser")
    theme = prompt_choice("Theme", themes, NAMES, default_theme)
    profiles = available[theme]
    current_profile = state.get("profile") if state else None
    default_profile = current_profile if current_profile in profiles else profiles[-1]
    labels = {p: f"{p}  {PROFILE_NAMES[p]}" for p in profiles}
    profile = prompt_choice("Display profile", profiles, labels, default_profile)
    return theme, profile


def status(args):
    state = backend.load_state(args.root)
    manager = backend.safe_path(args.root, backend.MANAGER)
    print("Theme manager: installed" if manager.is_file() else "Theme manager: running from checkout")
    if not state:
        print("No Evangelion theme is currently configured.")
        return 0
    print(f"Configured theme: {NAMES.get(state['theme'], state['theme'])}")
    print(f"Display profile: {state['profile']}")
    print(f"Requested graphics mode: {state['gfxmode']}")
    previous = state.get("previous")
    if previous:
        print(f"Previous choice: {NAMES.get(previous['theme'], previous['theme'])}, {previous['profile']}, {previous['gfxmode']}")
    else:
        print("Previous choice: none; uninstall restores the prior GRUB appearance.")
    return 0


def common_args(args):
    result = ["--root", str(args.root), "--source", str(args.source)]
    if args.dry_run:
        result.append("--dry-run")
    else:
        result.append("--quiet")
    if args.generator:
        result += ["--generator", str(args.generator)]
    return result


def apply_choice(args, theme, profile, deploy=False):
    theme, profile = theme_id(theme), profile_id(profile)
    mode = args.gfxmode
    # Changing only the theme should keep a user's explicit larger framebuffer.
    state = backend.load_state(args.root)
    if mode is None and state and state.get("profile") == profile:
        mode = state.get("gfxmode")
    command = ["install", "--theme", theme, "--profile", profile] + common_args(args)
    if mode:
        command += ["--gfxmode", mode]
    if deploy:
        command.append("--install-manager")
    result = backend.main(command)
    if result == 0 and not args.dry_run:
        print(f"\n{NAMES[theme]} is configured for the next boot.")
        if deploy:
            print("Switch themes from any directory with: sudo eva")
    return result


def parser():
    result = argparse.ArgumentParser(prog="eva", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  sudo eva
  sudo eva set wunder 1080p
  sudo eva set eva01 1440p --gfxmode 2560x1600
  sudo eva status
  sudo eva rollback
  sudo eva uninstall

No command opens the chooser in an interactive terminal. Rollback restores
the previous Evangelion choice; uninstall restores the prior GRUB appearance.
""")
    result.add_argument("command", nargs="?", choices=("choose", "set", "list", "status", "rollback", "uninstall", "install", "help"))
    result.add_argument("theme", nargs="?", help="eva01, wunder or eva02")
    result.add_argument("profile", nargs="?", help="720p, 1080p or 1440p")
    result.add_argument("--theme", dest="theme_option", help=argparse.SUPPRESS)
    result.add_argument("--profile", dest="profile_option", help=argparse.SUPPRESS)
    result.add_argument("--gfxmode", help="exact firmware mode, at least the design dimensions")
    result.add_argument("--dry-run", action="store_true", help="show changes without writing files")
    result.add_argument("--no-apply", action="store_true", help="install command and theme catalog without changing GRUB")
    result.add_argument("--root", type=Path, default=Path("/"), help="staging root; defaults to the live host")
    result.add_argument("--source", type=Path, default=ROOT / "themes", help=argparse.SUPPRESS)
    result.add_argument("--generator", type=Path, help=argparse.SUPPRESS)
    return result


def main(argv=None):
    cli = parser()
    args = cli.parse_args(argv)
    try:
        args.root = args.root.resolve(strict=True)
        args.source = args.source.resolve()
        if args.command == "help" or (args.command is None and not (sys.stdin.isatty() and sys.stdout.isatty())):
            cli.print_help()
            return 0
        command = args.command or "choose"
        if args.theme and args.theme_option or args.profile and args.profile_option:
            raise backend.InstallError("Supply theme and profile once, as positional values or named options.")
        theme, profile = args.theme or args.theme_option, args.profile or args.profile_option
        if command not in ("install", "set") and (theme or profile):
            raise backend.InstallError(f"{command} does not take a theme or profile.")
        if args.no_apply and command != "install":
            raise backend.InstallError("--no-apply is only for install.sh.")
        if args.no_apply and (theme or profile or args.gfxmode):
            raise backend.InstallError("--no-apply cannot be combined with a theme, profile or graphics mode.")
        if args.gfxmode and command not in ("set", "choose", "install"):
            raise backend.InstallError(f"{command} does not take --gfxmode.")
        if command == "list":
            available = catalog(args.source)
            for item, profiles in available.items():
                print(f"{NAMES[item]:<8} {'  '.join(profiles)}")
            if not available:
                print("No validated themes are available.")
            return 0
        if command == "status":
            return status(args)
        if command in ("rollback", "uninstall"):
            return backend.main([command] + common_args(args))
        if command == "install" and (args.no_apply or (not theme and not profile and not (sys.stdin.isatty() and sys.stdout.isatty()))):
            if args.gfxmode:
                raise backend.InstallError("Noninteractive installation with --gfxmode requires a theme and profile.")
            result = backend.main(["setup"] + common_args(args))
            if result == 0 and not args.dry_run:
                print("\nEvangelion theme manager is installed. GRUB appearance is unchanged.")
                print("Choose a theme with: sudo eva")
            return result
        if bool(theme) != bool(profile):
            raise backend.InstallError("set requires both a theme and a profile, for example: eva set wunder 1080p")
        if not theme:
            theme, profile = guided(args)
        return apply_choice(args, theme, profile, deploy=command == "install")
    except (EOFError, KeyboardInterrupt):
        print("\nCancelled.", file=sys.stderr)
        return 130
    except (backend.InstallError, OSError, ValueError, KeyError) as error:
        print(f"eva: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
