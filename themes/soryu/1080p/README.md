# Soryu, 1080p

Fixed 1920×1080 canvas, centered on larger display modes.

Install with the shared `install.sh` or `sudo eva` chooser. Four horizontal cards display real GRUB entries, with wrapped titles and live numbering. Very long titles end with an ellipsis when the card is full. Left and Right move between cards; Up and Down also work. Enter boots the selected entry or opens its submenu. Larger menus scroll. The countdown uses the actual timeout and disappears completely when cancelled.

The packaged native GRUB card module loads automatically. Python, jq and a compiler are not required. See [compatibility and installation](../../../docs/ADVANCED.md) and [licenses](../../../docs/NOTICE.md).

Selecting an entry uses the shared full-screen console handoff with real boot messages and no added delay.
