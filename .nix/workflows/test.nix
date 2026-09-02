{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages.test = pkgs.writeShellScriptBin "test" ''
      PATH+=$PATH:${pkgs.nimble}/bin/
      PATH+=$PATH:${pkgs.nim}/bin/
      nimble test
    '';
    apps.test = {
      type = "app";
      program = "${self'.packages.test}/bin/test";
    };
    githubActions.workflows.test = {
      name = "Test";
      on = {
        push.branches = ["development"];
      }; # on
      jobs = {
        test = {
          name = "Run all tests";
          runsOn = "ubuntu-latest";
          steps = [
            {uses = "actions/checkout@v4";}
            {uses = "cachix/install-nix-action@v31";}
            {
              name = "Generate documentation";
              id = "build";
              run = "nix run .#test";
            }
          ]; # steps
        }; # build
      }; # jobs
    }; # githubActions.workflows.docgen
  }; # perSystem
}
