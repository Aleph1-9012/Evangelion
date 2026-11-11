# Version 2.2.1

- Fixed Fedora BLS snapshots rejecting TuneD's `$tuned_initrd` suffix. Initrd paths and supported GRUB variables retain their order, including optional overlays.
- Added a reason to BLS snapshot rejection messages while keeping the live native-menu fallback.
- Separated the selected theme's files from catalog scans and stopped installation planning when a file inventory fails.
- Consolidated GRUB command parsing and removed redundant installer work without changing boot actions, theme switching or recovery behavior.
- Refreshed all eight README previews with native 2560×1440 captures and full-resolution links, preserving the existing theme order.

Installation and theme switching still use Bash, awk and standard Linux tools.
Python, jq and a compiler are not required. Soryu's supported GRUB versions
and platforms are unchanged from 2.2.0.

# Version 2.2.0

- Fixed GRUB 2.12 submenu rendering without changing the artwork or centered padding.
- Fixed an awk function-name conflict that prevented installation with mawk.
- Added checked Fedora BLS entries with native IDs, kernel-update refreshes and a live native-menu fallback.
- Preserved Fedora's stored kernel options during theme installation when its generator supports `--no-grubenv-update`.
- Restricted Soryu's card module to the supported GRUB versions and platforms, checked again on each configuration refresh.
- Added `sudo eva refresh`. After a catalog-only update with `--no-apply`, the next refresh, including the automatic one after a kernel update, applies the updated boot helper and the current theme's updated files.
- Made `eva refresh` regenerate native GRUB entries even when the theme and settings are unchanged. Identical output keeps the existing configuration backup.
- Clarified that manually applying updated theme files saves the old version in the rollback slot; `eva refresh` preserves the existing rollback choice.

Soryu's cards are enabled on GRUB 2.12 and 2.14 with x86-64 UEFI, and
GRUB 2.14 with 32-bit PC BIOS. Other combinations, including GRUB 2.16,
use the console menu.

# Version 2.1.0

- Reduced countdown redraw work in Ayanami, Pen-Pen and SEELE by cropping timer masks without changing their appearance or timing.
- Reduced timer font sizes and removed unused transparent images from the themes.
- Sped up catalog loading, installation and rollback checks by reading font headers in fewer steps, hashing files in batches and skipping unchanged file copies.
- Refreshed SEELE's artwork, preview and wallpaper with the complete supplied design.
- Added automatic recovery when only the managed `GRUB_THEME`, `GRUB_FONT` or `GRUB_GFXMODE` assignments are missing. Other conflicting edits still stop installation before files are changed.

All eight themes retain their 720p, 1080p and 1440p profiles, live countdowns,
navigation and full-screen console boot messages. Installation and theme
switching still use Bash, awk and standard Linux tools. Python, jq and a
compiler are not required.

## Upgrade

From the new download, run `sudo ./install.sh` and select your theme and
profile. Applying a theme updates the shared boot helper as well as its
artwork. Existing timeout and default entry are preserved. If the theme's
runtime files change, the old installed version replaces the saved rollback
choice.
A catalog-only update with `--no-apply` leaves the active boot helper in place.

See [installation and compatibility](ADVANCED.md) for graphics modes,
Soryu's native card module and recovery commands. See
[boot messages](BOOT_CONSOLE.md) for UKI and Secure Boot behavior.

# Version 2.0.0

- Fixed Soryu's Right Arrow booting the current entry. Left and Right now move between cards, including submenus and scrolling menus. Enter boots the selected entry. Up/Down and editor/console cursor movement are preserved.

- Added Ayanami, Soryu, Pen-Pen and SEELE, bringing the collection to eight themes.
- Included 720p, 1080p and 1440p profiles and matching 3840×2160 wallpapers for every theme.
- Added Soryu's horizontal cards, wrapped real entry titles and scrolling live numbers.
- Made the new countdowns follow the actual GRUB timeout and disappear completely when cancelled.
- Tied Ayanami and SEELE number badges to real entries, including short menus and submenus.
- Kept the shared full-screen console handoff with real boot messages and no added delay.
- Replaced the installer and boot helper's Python and jq dependencies with Bash and awk.
- Preserved theme switching, centered padding, rollback, ownership checks and uninstall restoration.
