{
  description = "Hyprland easymotion window hints";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = {
    self,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux"];
    eachSystem = f:
      nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
  in {
    packages = eachSystem (pkgs: {
      default = pkgs.callPackage ./nix/package.nix {src = ./.;};
      hypr-easymotion = pkgs.callPackage ./nix/package.nix {src = ./.;};
    });

    devShells = eachSystem (pkgs: {
      default = pkgs.mkShell {
        packages = [
          pkgs.zig
          pkgs.pkg-config
          pkgs.wayland
          pkgs.wayland-protocols
          pkgs.cairo
          pkgs.pango
          pkgs.libxkbcommon
          pkgs.glib
        ];
      };
    });

    formatter = eachSystem (pkgs: pkgs.alejandra);
  };
}
