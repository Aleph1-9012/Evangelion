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

## Upgrade

From the new download, run `sudo ./install.sh` and select your theme and
profile. Applying a theme updates the shared boot helper as well as its
artwork. Existing timeout, default entry and rollback choices are preserved.
A catalog-only update with `--no-apply` leaves the active boot helper in place.

See [installation and compatibility](ADVANCED.md) for graphics modes,
Soryu's native card module and recovery commands. See
[boot messages](BOOT_CONSOLE.md) for UKI and Secure Boot behavior.
