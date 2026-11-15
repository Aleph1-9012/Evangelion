# Console boot messages

Every installation uses a graphical theme for choosing an OS, then switches to a full-screen console when an entry starts. GRUB displays the selected entry name or, for native Fedora Linux entries, its boot ID. Linux entries show kernel, initramfs and system startup messages as the OS produces them. There is no added sleep, animation or progress simulation.

All eight themes use the same installer and boot helper. New themes listed in `themes/catalog.json` inherit the handoff. The theme files give GRUB's terminal the full screen, which also prevents the small empty rectangle during stock GRUB's initial clear.

## Adding future themes

Every new theme must use the shared installer and console handoff. Add its ID and display name to `themes/catalog.json`, and keep these properties in every profile's `theme.txt`:

```text
terminal-font: "Evangelion terminal Regular 16"
terminal-left: "0"
terminal-top: "0"
terminal-width: "100%"
terminal-height: "100%"
terminal-border: "0"
```

Each profile also supplies a one-pixel desktop image in its padding color.
GRUB 2.12 requires this image to avoid a bitmap error when opening submenus.
The artwork remains a separate, centered image at the profile's native size.

Package the matching terminal font with each profile and refresh its asset hashes. The graphical menu must switch to real console output when an entry starts, with no added delay. Keep this behaviour in the shared boot helper so fixes apply to every theme. Check each new profile's menu and boot handoff in a VM before release.

## What changes

The installer keeps the original `/etc/grub.d/` scripts. Its managed block in `/etc/default/grub` directs GNU `grub-mkconfig` through `/var/lib/evangelion-grub/boot/grub.d/00_console`. This proxy runs the original scripts in their usual order, then processes their output. Kernel updates that run `grub-mkconfig` therefore keep the handoff and read the current boot images.

Each generated `menuentry` starts with `terminal_output console`, `clear` and a selected-entry message. Submenus stay graphical until a boot entry is chosen. Existing loading messages and errors remain visible. Entry titles, menu text, fonts and system locale are preserved. For Ayanami and SEELE, the generator also adds number-icon classes to explicit entries and submenus. Existing IDs, classes and boot commands retain their meaning; submenu numbering starts again at 01. The added selected-entry message is in English.

For direct Linux entries, the helper removes `quiet`, splash and conflicting display settings. It enables kernel and systemd messages, restores the text cursor and disables Plymouth for that boot. Existing root, encryption, resume, recovery and other non-display arguments are retained. Existing `console=` destinations are respected; otherwise it adds `console=tty0`.

For a locally resolvable unified kernel image, or UKI, the helper reads its PE `.linux` and `.cmdline` sections. When Secure Boot is known to be disabled, it supplies the embedded arguments with the same display changes through GRUB's EFI invocation. The image itself is untouched. Windows and other EFI applications keep their arguments.

## Compatibility

Requires GNU GRUB with the standard `grub-mkconfig` generator directory, Bash, awk and standard Linux command-line tools. Python and jq are not required. Both `/boot/grub` and `/boot/grub2` installation layouts are supported.

With Secure Boot enabled or unreadable, the helper keeps a UKI's arguments unchanged. The console handoff still happens, but an image with embedded `quiet` or splash settings may hide Linux messages. The installer does not disable Secure Boot or rebuild or sign images. See [systemd-stub](https://man.archlinux.org/man/systemd-stub.7.en) for EFI command-line rules.

The helper processes explicit entries emitted during menu generation. Entries loaded later through `source`, `configfile`, runtime variables or another bootloader may require changes in that source. EFI images that cannot be resolved uniquely on local boot mounts keep their original arguments. Failed installation restores the previous files and configuration.

## Fedora BLS entries

Fedora's `blscfg` reads the current boot entries when GRUB builds its menu.
A kernel addition, removal or edit is visible at the next boot. Fedora handles
entry order, saved IDs, access rules, initrds and TuneD overlays. The menu
uses the selected theme. Native BLS entries supply their own classes, so the
number badges in Ayanami and SEELE are available only for explicit entries
whose row number is known.

When a Fedora type-1 Linux entry calls `load_video`, the boot helper
switches GRUB to the full-screen firmware console and prints the selected
boot ID. Fedora then loads the kernel and initrd. Fedora's existing command
line controls verbosity, Plymouth and console routing. An entry with
`quiet rhgb` can show fewer messages or a splash after Linux takes over.
A serial-only kernel console sends Linux messages to that serial port.

The installer leaves the native BLS files and saved kernel options intact.
Kernel-install can still refresh the managed theme and GRUB configuration.
Booting uses Fedora's installed EFI loader and its built-in commands.

## Upgrade and removal

Install a theme again from the updated download to activate this behaviour. `sudo ./install.sh --no-apply` updates only the chooser and catalog; it does not change the active boot configuration until the next `sudo eva refresh`. The kernel-install hook runs that refresh after kernel additions and removals, so on those systems the updated helper takes effect with the next kernel update. The old patch export command and patch payload have been removed from the package. An already patched GRUB installation can use the new handoff without rebuilding GRUB.

`sudo eva uninstall` removes the managed generator override and restores normal generation from the original scripts. It also removes unchanged owned helper files. It preserves unrelated user changes and keeps the previous generated configuration for recovery. See [installation and restoration](ADVANCED.md) for dry runs, ownership checks and rollback.
