{
  description = "Nim-centric development environment";

  inputs = {
    # Latest commit in the branch nixos-25.11
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    # Flake-parts
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ { flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; }
  {
    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ]; # systems

    perSystem = { pkgs, ... }: {
      # packages.paquete = pkgs.paquete;
      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          # Nim
          nim
          nimble
          nph
          clang
          emscripten
        ]; # buildInputs
      }; # devShells.default
    }; # perSystem
  }; # flake-parts.lib.mkFlake
}
