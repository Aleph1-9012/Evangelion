# Installation and restoration

The themes use GRUB 2's graphical theme format. The Linux installer requires Bash, jq and an existing GRUB installation with `/etc/default/grub` and `/etc/grub.d/00_header`. It detects `/boot/grub/grub.cfg` or `/boot/grub2/grub.cfg`, and accepts either `grub-mkconfig` / `grub-script-check` or `grub2-mkconfig` / `grub2-script-check`. It does not install GRUB, change firmware entries, alter kernel arguments, install wallpapers, or reboot.

The installer preserves your existing timeout, default boot entry and menu-generation scripts.

There is no distribution-name check. The installation paths and available GRUB tools determine whether the installer can run. Arch Linux with GRUB 2.14 is the hardware-tested environment; the other directory and command layouts are checked in disposable staging roots, not full installations of every distribution.

If both GRUB directories contain configurations, select the active one explicitly, for example `sudo ./install.sh ramiel 1080p --grub-dir /boot/grub2`. Later operations use the directory recorded in the installed theme's ownership paths. The installer writes the main configuration there, not an EFI forwarding file under `/boot/efi/EFI/`.

The paths below show `/boot/grub`; on systems using `/boot/grub2`, the configuration and active theme use that directory instead.

## Select a theme and graphics mode

The repository includes ready-to-use theme files. Install once from the downloaded folder:

```sh
sudo ./install.sh
```

The interactive chooser asks for a theme and display profile. Installation adds `/usr/local/bin/eva` and a catalog under `/usr/local/share/evangelion`. The catalog includes all validated profiles and the Bash scripts and licenses. Only the selected profile goes into `/boot`.

Users can then switch from any directory:

```sh
sudo eva
sudo eva set wunder 1080p
sudo eva set eva02 1080p
sudo eva set ramiel 1080p
sudo eva set eva01 1440p --gfxmode 2560x1600
eva list
sudo eva status
```

The chooser defaults to the current theme and profile. `list` requires no root privileges. `status` reports the configured theme, profile, requested graphics mode and previous choice. It does not claim to measure the framebuffer used by firmware. Long-lived command and catalog files are independent of the original checkout.

Run `sudo ./install.sh --no-apply` to install the command and catalog without changing GRUB. When invoked without arguments in a noninteractive terminal, `install.sh` also installs only the catalog and command. An explicit `choose` requires an interactive terminal. Invalid choices prompt again; EOF or Ctrl-C exits before applying a selection. No extra confirmation follows a valid selection.

Initial direct selection accepts `sudo ./install.sh eva01 1440p`, or the original named options. Add `--dry-run` to any install, switch, rollback or uninstall to see the exact file changes without writing them. For example:

```sh
./install.sh eva01 1440p --gfxmode 2560x1600 --dry-run
sudo eva set wunder 1440p --dry-run
```

Only generated EVA-01, Wunder, EVA-02 and Ramiel profiles with a matching `runtime-ready.json` record, PNG artwork, `theme.txt` and `fonts/*.pf2` can be installed. The installer checks the recorded canvas dimensions and every asset's SHA256, requires every referenced image and styled-box center slice, and matches theme font names against the names embedded in the packaged PF2 files. Changed, missing or unrecorded assets require a rebuild.

The installer and chooser use Bash with `jq` to read the asset and ownership records. To refresh the installed command and theme catalog, run `sudo ./install.sh --no-apply` from the updated folder. This preserves the current choice, rollback snapshot and original GRUB settings.

The three design sizes are `720p`, `1080p` and `1440p`. Graphics mode and design size are separate. A larger mode keeps the design at its native dimensions, centered with padding. For example, `1440p --gfxmode 3840x2160` uses the 2560×1440 design on a 3840×2160 framebuffer. There is no separately scaled 4K design. The installer rejects a mode smaller than the selected design.

Changing only the theme while keeping the same profile preserves the previous requested graphics mode. On first selection or a profile change, 720p selects 1280×720 and 1080p selects 1920×1080. The 1440p profile preserves an existing literal `GRUB_GFXMODE` if both dimensions are at least 2560×1440; otherwise it selects 2560×1440. For example, an existing 2560×1600 mode is preserved. Shell expressions and mode preference lists are not evaluated to choose this default. `--gfxmode` always takes precedence.

Check the available modes using `videoinfo` in real GRUB before a hardware test. A desktop mode does not establish firmware support. The loader returns to a plain console menu if the selected mode cannot initialize. The existing entries and timeout remain usable there.

GRUB 2.14 appends an `auto` fallback internally even when `gfxmode` names one exact mode. The generated loader appends a deliberately invalid mode token, `evangelion_no_auto_fallback`, so a failed exact mode returns an error before GRUB reaches that hidden fallback. The token is an implementation detail, not a mode to enter in the installer. Supported and unsupported branches were tested in real GRUB. Revalidate this behavior when changing GRUB versions.

A dry run only previews changes. It does not copy theme files or activate a theme. To install the reviewed selection, rerun without `--dry-run`, then check the configured choice:

```sh
sudo ./install.sh --theme eva01 --profile 1440p --gfxmode 2560x1600
sudo eva status
```

Reboot when installation has completed successfully and status shows the intended choice. If installation reports an error, resolve it before rebooting. The installer needs write access to the boot destination.

After installation, switch using the persistent command:

```sh
sudo eva set wunder 1440p
```

Selecting the same theme, profile and mode again makes no changes when the owned files and state already match. It also preserves the previous choice for rollback. No duplicate settings or extra backup generations accumulate.

## Exact changes

The dry run prints the complete proposed loader, a unified diff of `/etc/default/grub`, and the size and SHA256 of every runtime file to copy. It performs no writes and does not run configuration generation.

For a 1440p profile in 2560×1600 mode, the added defaults block is:

```sh
# BEGIN EVANGELION GRUB (managed; use install.sh --uninstall)
# The late loader selects the theme only after the exact mode succeeds.
GRUB_THEME=""
GRUB_FONT=""
GRUB_GFXMODE="2560x1600"
GRUB_TIMEOUT_STYLE="menu"
# END EVANGELION GRUB
```

Prior assignments remain in place. The last managed assignments suppress early theme loading and request the visible menu; `/etc/grub.d/99_evangelion` then selects the theme after the exact mode initializes. The hook loads the existing `$prefix/fonts/unicode.pf2` terminal font and all packaged PF2 fonts. Keep the distro's Unicode font installed for console and editor readability.

The shared hook enables `eva_defer_boot_terminal=1` after the graphical terminal starts successfully. With the [optional GRUB 2.14 patch](GRUB_PATCH.md), this preserves the menu during silent manual selection for EVA-01, Wunder, EVA-02 and Ramiel, across all three profiles. Stock GRUB ignores the setting. The hook clears it before initializing the display, so console fallback does not enable it. The installer embeds the patch and exports it into the installed catalog; `eva grub-patch` prints a copy. Rebuilding GRUB remains separate. The installer does not replace GRUB binaries or modules.

The installer owns these locations:

| Location | Purpose |
| --- | --- |
| `/boot/grub/themes/evangelion/` | One active runtime profile; the manifest tracks individual files |
| `/etc/grub.d/99_evangelion` | Generated executable shell hook emitting the GRUB loader |
| One marked block in `/etc/default/grub` | Theme settings, removable without restoring the entire file |
| `/var/lib/evangelion-grub/state.json` | Current choice, original relevant setting lines and owned-file hashes |
| `/var/lib/evangelion-grub/grub.cfg.previous` | Exactly one previous generated configuration, retained for recovery |
| `/var/lib/evangelion-grub/previous/` | One previous runtime snapshot for theme rollback |
| `/usr/local/bin/eva` | Persistent executable command |
| `/usr/local/share/evangelion/` | Manager, all validated profiles and license files |
| `/var/lib/evangelion-grub/manager.json` | Ownership hashes for the installed command and catalog |

`grub-mkconfig` writes a temporary candidate beside the existing `/boot/grub/grub.cfg`. The installer runs `grub-script-check`, checks that the exact generated loader is present, and only then replaces the active configuration. File writes use same-directory temporary files and atomic replacement. Generation, syntax-check and ordinary write failures restore the files changed by that operation. Temporary candidate files are removed on success and failure.

The backup stores one previous generated configuration and rotates only after successful validation. It remains after uninstall. It is an emergency artifact, not the normal uninstall mechanism; blindly copying an old generated file could discard boot-entry changes. Full transaction recovery after power loss or process termination with `SIGKILL` is not implemented. Run installation as a maintenance operation with a recovery path available.

## Roll back a theme choice

```sh
sudo eva rollback --dry-run
sudo eva rollback
```

Rollback restores the previous Evangelion theme, profile and graphics mode from its verified runtime snapshot. It regenerates configuration using the current system, preserving unrelated settings and boot-entry changes. The outgoing choice becomes the single previous snapshot, so another rollback switches back. A failed rollback restores the state from before that operation.

The first Evangelion selection has no previous Evangelion choice. Use `uninstall` to restore the pre-Evangelion appearance. Runtime snapshots remain bounded to one previous choice and do not depend on the old package still being available.

## Uninstall

Use the same script that installed the themes:

```sh
sudo ./install.sh --uninstall --dry-run
sudo ./install.sh --uninstall
```

The `uninstall` subcommand is equivalent to `--uninstall`. The installed command also supports removal:

```sh
sudo eva uninstall --dry-run
sudo eva uninstall
```

Uninstall removes the marked block and loader, regenerates the configuration from the current system, and removes owned runtime files, snapshots, command and catalog files whose hashes still match. This restores the prior theme settings while retaining unrelated edits made after installation. Files you modified and files outside the installer's ownership remain in place and are reported. Empty owned directories are removed. Catalog-only uninstall does not touch GRUB. Repeating `./install.sh --uninstall` after removal makes no changes. Installations made with the earlier separate scripts remain removable with this combined script.

If someone edits the managed defaults block or generated loader, the operation stops before writing anything. The ownership record contains the original generated block. Reconcile the edit with that record before retrying. Installer switching also refuses to overwrite runtime files you modified. It never deletes another theme directory.

## Hardware observations

EVA-01, Wunder and EVA-02 have booted successfully on an Arch Linux machine. All three themes have also passed checks in disposable UEFI virtual machines at 720p, 1080p, 1440p and larger padded modes. Physical firmware support for every mode and Secure Boot compatibility remain untested.

Ramiel passed the same virtual-machine display modes, including menu navigation, countdown, submenu boot and console fallback. A physical-machine test is still pending.

EVA-02 shows five rows. Its fixed 01–05 labels mark the visible slots while longer menus scroll. Entry titles come from GRUB. Six Caps provides the condensed entry lettering; symbols and languages outside the font's coverage depend on GRUB's fallback fonts. The countdown uses Intel One Mono and a continuous bar. The reference image's small arrow at the fill endpoint is omitted from the live countdown.

Ramiel shows five rows with Inter lettering and an orange selection marker. Its thin countdown bar and numeric caption disappear when a key cancels automatic boot. Longer menus scroll. Long titles are clipped within the menu width, including some common multiword entries; use GRUB's entry editor to inspect the full title.

An empty terminal box over the theme and a pause of about 10 seconds after selecting an entry have been reported. The empty box was reproduced in GRUB 2.14 VMs before any kernel ran, with EVA-01 and all four Marathon themes. The [optional GRUB patch](GRUB_PATCH.md) defers that empty clear during silent manual selection. Loading messages, errors, console and editor use still display the terminal. Automatic boot retains its boot announcement. The reported delay remains unresolved.
