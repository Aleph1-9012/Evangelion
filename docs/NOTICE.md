# Artwork and font notices

The project's Apache-2.0 license is included in [LICENSE](../LICENSE).

The EVA-01, Wunder, EVA-02, Ramiel, Ayanami, Soryu, Pen-Pen and SEELE artwork and matching wallpapers were supplied for this project. The GRUB backgrounds, selection indicators and countdown graphics are derived from that artwork.

## Fonts

EVA-01 uses Space Mono Regular. Wunder uses JetBrains Mono Regular. EVA-02 uses Six Caps for menu entries and Intel One Mono Regular for its countdown. Ramiel uses Inter Regular for both. Ayanami and SEELE use Share Tech Mono Regular. Pen-Pen uses M PLUS Rounded 1c Medium for entries and countdown digits. Ayanami and SEELE also package PNG number badges derived from their supplied number paths and Share Tech Mono. Soryu uses Chakra Petch Regular for entries, numbers and countdown digits. All themes include a JetBrains Mono terminal font. The fonts are included in GRUB's PF2 format, and their SIL Open Font License texts are distributed with the themes.

- Space Mono: [source](https://github.com/google/fonts/tree/main/ofl/spacemono) · [license](licenses/space-mono/OFL.txt)
- JetBrains Mono: [source](https://github.com/JetBrains/JetBrainsMono) · [license](licenses/jetbrains-mono/OFL.txt)
- Six Caps: [source](https://github.com/google/fonts/tree/main/ofl/sixcaps) · [license](licenses/six-caps/OFL.txt)
- Intel One Mono: [source](https://github.com/intel/intel-one-mono/tree/V1.4.0) · [license](licenses/intel-one-mono/OFL.txt)
- Inter: [source](https://github.com/rsms/inter) · [license](licenses/inter/OFL.txt)
- Share Tech Mono: [source](https://github.com/google/fonts/tree/main/ofl/sharetechmono) · [license](licenses/share-tech-mono/OFL.txt)
- M PLUS Rounded 1c Medium: [source](https://github.com/google/fonts/tree/main/ofl/mplusrounded1c) · [license](licenses/m-plus-rounded-1c/OFL.txt)

- Chakra Petch: [source](https://github.com/google/fonts/tree/main/ofl/chakrapetch) · [license](licenses/chakra-petch/OFL.txt)

The themes preserve their other lettering as artwork. This includes Ayanami's Noto Serif JP and Aoyagi Kouzan T headings, Pen-Pen's M PLUS Rounded 1c ExtraBold Japanese lettering, and SEELE's Bodoni Moda and Noto Serif JP headings. Those fonts are not needed by the live GRUB controls.

## Native card menu

Soryu includes `evangelion_cards.mod` for horizontal cards and wrapped live
titles. This module is licensed under GPL-3.0-or-later, separately from the
project's Apache-2.0 files. Its viewer setup derives from GNU GRUB,
copyright 2008 Free Software Foundation, Inc. The card component is
copyright 2026 Evangelion contributors.

The [GPL license](licenses/grub-cards/COPYING) and
[complete corresponding source](licenses/grub-cards/source.tar.xz) accompany
the binaries. The source archive contains the module, build recipe and the
unmodified GNU GRUB 2.14 source distribution. It is included for license
compliance and modification; users do not need to extract or build it.

## Acknowledgments

Centered padding on larger displays follows the approach used in [Sidonia](https://github.com/Aleph1-9012/Sidonia).
