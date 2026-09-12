{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages = {
      test = pkgs.writeShellScriptBin "test" ''
        PATH+=$PATH:${pkgs.nimble}/bin/
        PATH+=$PATH:${pkgs.nim}/bin/
        nimble test
      ''; # test
    }; # packages
    apps = {
      test = {
        type = "app";
        program = "${self'.packages.test}/bin/test";
      }; # test
    }; # apps
    githubActions.workflows.test = {
      name = "Test";
      on.push.branches = ["dev"];
      on.push.paths = ["intrashell.nimble"];
      permissions = {
        contents = "write";
      }; # permissions
    }; # githubActions.workflows.test
    githubActions.workflows.test.jobs = {
      test = {
        name = "Execute all tests";
        runsOn = "ubuntu-latest";
        outputs = {
          modified = "\${{ steps.modified.outputs.modified }}";
        };
        steps = [
          {
            uses = "actions/checkout@v7";
          }
          {uses = "cachix/install-nix-action@v31";}
          {
            name = "Run tests";
            run = "nix run .#test";
          }
        ]; # steps
      }; # test
    }; # githubActions.workflows.test.jobs
  }; # perSystem
}
