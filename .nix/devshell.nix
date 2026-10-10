{
  perSystem = { pkgs, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        nim
        nimble
        swig
        rust-bindgen
        zig # translate-c
      ];
    };
  };
}

