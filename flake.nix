{
  description = "A lightweight library for using shared libraries as dynamic modules in Nim. This is achieved by enforcing a common procedure signature that simulates the behaviour of CLI applications (which are state-machines).";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";
    wrapper-modules.url = "github:BirdeeHub/nix-wrapper-modules";
    github-actions-nix.url = "github:synapdeck/github-actions-nix";
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake
  {inherit inputs;}
  ({
    imports = [
      (inputs.import-tree ./.nix)
      inputs.github-actions-nix.flakeModules.default
    ];
  });
}

