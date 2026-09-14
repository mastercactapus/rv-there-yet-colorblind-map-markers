{
  description = "Colorblind-friendly map markers for RV There Yet? (UE5 game mod)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
          name = "rv-there-yet-colorblind";

          packages = with pkgs; [
            # Rust toolchain -- for building retoc/repak (UE5 IoStore + pak tooling)
            cargo
            rustc
            rustfmt
            clippy
            pkg-config
            openssl

            # retoc dlopen()s a prebuilt Oodle .so, which links against libstdc++
            stdenv.cc.cc.lib

            # Scripting for poking at .utoc/.uasset binary formats
            (python3.withPackages (ps: with ps; [ pillow ]))

            # UE4SS embeds LuaJIT (Lua 5.1) -- used here to syntax-check the mod
            luajit

            # Image/texture inspection and conversion
            imagemagick

            # General binary spelunking
            xxd
            ripgrep
            jq
            file
            unzip
            zip
            curl
          ];

          shellHook = ''
            export CARGO_HOME="$PWD/.cargo-home"
            export PATH="$CARGO_HOME/bin:$PATH"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export RV_GAME_DIR="''${RV_GAME_DIR:-$HOME/.local/share/Steam/steamapps/common/Ride}"
            echo "rv-there-yet-colorblind dev shell"
            echo "  game dir: $RV_GAME_DIR"
          '';
        };
      });
}
