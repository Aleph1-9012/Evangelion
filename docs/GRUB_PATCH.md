# Optional GRUB patch for silent selection

EVA-01, Wunder, EVA-02 and Ramiel share support for a GRUB 2.14 patch that keeps the selected menu visible while a manually selected entry runs without printing output. It prevents GRUB's empty terminal clear from covering the artwork with a black rectangle.

**This requires GRUB built with the included patch.** The patch is embedded in the theme installer, which exports it into the installed catalog and enables the feature in its generated loader. Rebuilding and installing GRUB remain separate steps. Installing or copying a theme onto stock GRUB leaves its usual terminal behavior in place.

## Behavior

The loader enables `eva_defer_boot_terminal=1` after the graphical terminal starts and the theme is selected. This applies to all four themes and their 720p, 1080p and 1440p profiles, including larger modes using centered padding. The setting is cleared before display initialization and stays unset if graphics initialization falls back to the console.

The patch prepares a cleared terminal offscreen. It displays that terminal when text or an interactive cursor is needed. Loading messages, errors, the command console, and the editor remain visible. A normal clear or window teardown resets the deferred state.

Automatic boot still prints its boot announcement. An entry that prints a loading message will still show a terminal. This patch does not change kernel arguments, add Plymouth, or address a reported boot delay.

## Languages and appearance

The installer remains Bash. Its embedded payload is a patch to GRUB's C source; there is no conversion of the installer or theme format to another programming language.

The patch changes no displayed strings, translations, fonts, artwork, or menu layouts. The shared loader does not alter `lang` or `locale_dir`. Preserve your distribution's translation support and locale catalogs when building GRUB. Do not copy the earlier VM experiment's `--disable-nls` flag into a system build. A build with translations disabled could change the language of GRUB's own messages even though this patch does not require that change.

## Applying the GRUB source patch

The patch is embedded in [bin/install.sh](../bin/install.sh), based on the [GNU GRUB 2.14 release source](https://ftp.gnu.org/gnu/grub/grub-2.14.tar.xz). It modifies `grub-core/normal/menu.c` and `grub-core/term/gfxterm.c` and is licensed under [GPL-3.0-or-later](licenses/grub/COPYING). The checkout and user archive do not need a separate `patches/` folder.

For a distribution package, apply it during the GRUB package's source preparation step, then use the distribution's build and bootloader-update process. Preserve the distribution's existing build options, translations, and signing setup. Updating a theme or running `grub-mkconfig` alone does not patch GRUB or its boot image.

To export it and check an extracted GRUB 2.14 source tree, run these commands from the Evangelion checkout after replacing the example source path. Exporting only prints the patch; it requires no root privileges and makes no installation changes.

```sh
./install.sh --print-grub-patch > /tmp/evangelion-grub-2.14.patch
grub_source=/absolute/path/to/grub-2.14
patch --dry-run -d "$grub_source" -p1 < /tmp/evangelion-grub-2.14.patch
patch -d "$grub_source" -p1 < /tmp/evangelion-grub-2.14.patch
```

After installing the theme manager, `eva grub-patch` exports the same patch from any directory. The installer also stores it at `/usr/local/share/evangelion/patches/grub-2.14-deferred-terminal.patch`, with ownership tracking for upgrades and removal.

The patch is version-specific. A successful source application does not establish compatibility with a different GRUB release or a distribution's other patches.

Once a patched GRUB installation is available, reinstall the selected theme from this updated checkout, for example:

```sh
sudo ./install.sh eva01 1080p
```

The normal installer updates the shared loader and installed theme catalog. Refreshing only the catalog with `--no-apply` does not update an already installed loader; select a theme afterward to apply it.

For manual GRUB configuration, enable and export the public setting after selecting the graphical theme:

```grub
set eva_defer_boot_terminal=1
export eva_defer_boot_terminal
```

The internal variable `eva_internal_defer_clear` belongs to the patch and should not be configured manually. To disable the behavior in a manually maintained configuration, unset the public setting or set it to `0`. The managed Evangelion loader owns its setting; reinstalling a theme restores it to `1`.

Uninstalling Evangelion removes its generated loader and the opt-in setting. It does not remove a separately installed patched GRUB package.

## Validation

The updated shared loader was tested in QEMU/OVMF UEFI VMs using GRUB 2.14 built with translation support enabled. All twelve theme/profile combinations preserved the menu with zero changed pixels during silent manual selection. Returning to the menu, loading output, missing-kernel errors, console access, editor access, and a minimal Linux kernel/initramfs boot succeeded in every case.

Four additional 1080p cases confirmed that stock GRUB still boots each theme with the new loader, retaining its usual terminal behavior. A French-language case preserved silent selection and displayed translated errors and the continuation prompt. The 56 installer tests also passed, including upgrades from the published release, switching, rollback, removal, and both GRUB directory layouts.

These checks cover VMs and a minimal Linux guest. They do not establish physical-hardware, encrypted-disk, Windows chainloading, Secure Boot, or other GRUB-version compatibility.
