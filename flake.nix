{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      crane,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };
        craneLib = (crane.mkLib pkgs).overrideToolchain (
          p:
          p.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "rust-analyzer"
              "clippy"
            ];
            # targets = [ "wasm32-unknown-unknown" ];
          }
        );
        commonArgs = {
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            name = "source";
            filter =
              path: type: (builtins.match ".*otf$" path != null) || (craneLib.filterCargoSources path type);
          };
          strictDeps = true;
          buildInputs = [ ];
          version = "0.1.0";
          pname = "table-flow";
        };
        myCrate = craneLib.buildPackage (
          commonArgs
          // {
            cargoArtifacts = craneLib.buildDepsOnly commonArgs;

            postInstall = ''
              wrapProgram "$out/bin/table-flow" --prefix LD_LIBRARY_PATH : "${libPath}"
            '';

            nativeBuildInputs = with pkgs; [
              copyDesktopItems
              makeWrapper
            ];

            desktopItems = [
              (pkgs.makeDesktopItem {
                name = "table-flow";
                desktopName = "Table Flow";
                genericName = "Table-based analyzer";
                # icon = "picotron";
                exec = "table-flow ui";
                categories = [ "Office" ];
              })
            ];
          }
        );

        libPath =
          with pkgs;
          lib.makeLibraryPath [
            alsa-lib
            libGL
            libxkbcommon
            wayland
            systemd
            xorg.libX11
            xorg.libXcursor
            xorg.libXi
            xorg.libXrandr
          ];
      in
      {
        defaultPackage = myCrate;

        defaultApp = flake-utils.lib.mkApp {
          drv = myCrate;
        };

        devShell = craneLib.devShell {
          packages = with pkgs; [
            cargo-outdated
            cargo-nextest
            difftastic
            pre-commit
            tokei
            just
            pkg-config

            # We get rust from `craneLib.devShell`, so no need to add it here.
            # rust-stable

            alsa-lib
            systemd
            wayland
          ];
          GIT_EXTERNAL_DIFF = "${pkgs.difftastic}/bin/difft";
          LD_LIBRARY_PATH = libPath;

          # There's a bug in wgpu that means it doesn't handle wayland well.
          # The last update was from October 2024, so this is an ongoing issue.
          # It's also probably hardware-specific (specifically, the GL backend
          # might be bugged, but the Vulkan one may work), so let's disable
          # wayland for now.
          WAYLAND_DISPLAY = "";
        };
      }
    );
}
