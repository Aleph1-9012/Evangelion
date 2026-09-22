{
    description = "Flake to manage the Evangelion grub theme";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    };

    outputs =
        { self, nixpkgs }:
        let
            system = "x86_64-linux";
            pkgs = import nixpkgs { inherit system; };
        in
        with nixpkgs.lib;
        {
            nixosModules.default =
                { config, ... }:
                let
                    cfg = config.boot.loader.grub.evangelion-grub-theme;

                    evangelion-grub-theme = pkgs.stdenv.mkDerivation {
                        name = "evangelion-grub-theme";
                        src = "${self}";
                        installPhase = ''
                            mkdir -p $out
                            cp -r themes/* $out
                        '';
                    };
                in
                {
                    options = {
                        boot.loader.grub.evangelion-grub-theme = {
                            enable = mkOption {
                                type = types.bool;
                                default = false;
                                example = true;
                                description = ''
                                    Enable Evangelion grub theme.
                                '';
                            };
                            style = mkOption {
                                type = types.enum [
                                    "ayanami"
                                    "eva01"
                                    "eva02"
                                    "penpen"
                                    "ramiel"
                                    "seele"
                                    "soryu"
                                    "wunder"
                                ];
                                default = "ayanami";
                                description = "Choose one of the themes.";
                            };
                            resolution = mkOption {
                                type = types.enum [
                                    "720p"
                                    "1080p"
                                    "1440p"
                                ];
                                default = "1080p";
                                description = "Choose the resoluion for the theme.";
                            };
                        };
                    };

                    config = mkIf cfg.enable {
                        environment.systemPackages = [ evangelion-grub-theme ];

                        boot.loader.grub = {
                            theme = "${evangelion-grub-theme}/${cfg.style}/${cfg.resolution}";
                            splashImage = "${evangelion-grub-theme}/${cfg.style}/${cfg.resolution}/background.jpg";
                        };
                    };
                };
        };
}
