# Evangelion

Seven Evangelion themes for your GRUB boot menu: EVA-01, Wunder, EVA-02, Ramiel, Ayanami, Pen-Pen and SEELE. All include 720p, 1080p and 1440p profiles and matching 4K wallpapers.



## EVA-01

![EVA-01 preview](previews/EVA-01.png)

## Wunder

![Wunder preview](previews/Wunder.png)

## EVA-02

![EVA-02 preview](previews/EVA-02.png)

## Ramiel

![Ramiel preview](previews/Ramiel.png)

The Ayanami, Pen-Pen and SEELE previews below are captured from GRUB.

## Ayanami

![Ayanami preview](previews/Ayanami.png)

## Pen-Pen

![Pen-Pen preview](previews/Pen-Pen.png)

## SEELE

![SEELE preview](previews/SEELE.png)

## Install

Requires **Linux** with **GRUB 2** installed, plus **Bash**, **jq** and **Python 3.9 or newer**. Install jq with your distribution's package manager if needed.

The installer detects `/boot/grub` or `/boot/grub2` and the available GRUB tools. Tested on Arch Linux with GRUB 2.14.

```sh
git clone https://github.com/Aleph1-9012/Evangelion.git
cd Evangelion
sudo ./install.sh
```

Choose a theme and resolution: **720p**, **1080p** or **1440p**. After installation finishes successfully, reboot to see your theme.

Larger display modes can use the 1440p design centered with padding. See the [installation guide](docs/ADVANCED.md) for display options.

Selecting an OS switches to a full-screen console with live boot messages. This is the default for every theme and works with stock GRUB. See [boot behaviour and compatibility](docs/BOOT_CONSOLE.md).

## Switch themes

Run this from any folder:

```sh
sudo eva
```

Choose another theme or resolution. Your selection takes effect on the next boot. You can also select a theme directly:

```sh
sudo eva set ayanami 1080p
sudo eva set penpen 1080p
sudo eva set seele 1440p
```

## Uninstall

From the Evangelion folder, run:

```sh
sudo ./install.sh --uninstall
```

You can also run `sudo eva uninstall` from any folder. This restores your previous GRUB theme settings.

## Wallpapers

Download the matching 3840×2160 wallpaper and select it in your desktop wallpaper settings:

- [EVA-01 wallpaper](wallpapers/EVA01-wall.png)
- [Wunder wallpaper](wallpapers/Wunder-wall.png)
- [EVA-02 wallpaper](wallpapers/EVA-02-wall.png)
- [Ramiel wallpaper](wallpapers/Ramiel-wall.png)
- [Ayanami wallpaper](wallpapers/Ayanami-wall.png)
- [Pen-Pen wallpaper](wallpapers/Pen-Pen-wall.png)
- [SEELE wallpaper](wallpapers/SEELE-wall.png)

For more options, rollback and known limitations, read the [installation guide](docs/ADVANCED.md).

[License](LICENSE) · [Artwork and font notices](docs/NOTICE.md)
