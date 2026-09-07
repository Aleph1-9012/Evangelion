# EVA-02, 720p

Fixed 1280×720 GRUB canvas, centered with padding on larger modes.

Install through the repository's `install.sh` or `sudo eva` chooser. The loader selects the graphics mode and loads the packaged PF2 fonts.

Runtime files are `theme.txt`, `background.png`, `fonts/`, `selectors/` and `progress/`. `runtime-ready.json` records the files checked by the installer.

Entries and the countdown come from the existing GRUB configuration. 5 rows are visible; larger menus scroll.

See [installation](../../../docs/ADVANCED.md) and [artwork and font notices](../../../NOTICE.md).
