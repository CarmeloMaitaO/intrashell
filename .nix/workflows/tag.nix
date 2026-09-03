{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages.tag = pkgs.writeShellScriptBin "tag" ''
      PATH+=$PATH:${pkgs.git}/bin/
      version=$(<version)
      git config user.name "Git Bot"
      git config user.email "carmeloaugustomaitaorlando@gmail.com"
      git checkout main
      git merge development
      git tag $version
      git push -f --tags
    '';
    apps.tag = {
      type = "app";
      program = "${self'.packages.tag}/bin/tag";
    };
    githubActions.workflows.tag = {
      name = "tag";
      on = {
        workflowRun.workflows = ["Test"];
        push.branches = ["development"];
        push.paths = ["version"];
      }; # on
      permissions = {
        contents = "write";
      }; # permissions
      jobs = {
        tag = {
          name = "Run all tags";
          runsOn = "ubuntu-latest";
          steps = [
            {
              uses = "actions/checkout@v4";
              with_ = {
                fetch-depth = "0";
              };
            }
            {uses = "cachix/install-nix-action@v31";}
            {
              name = "Generate documentation";
              id = "build";
              run = "nix run .#tag";
            }
          ]; # steps
        }; # tag
      }; # jobs
    }; # githubActions.workflows.docgen
  }; # perSystem
}
