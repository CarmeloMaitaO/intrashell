{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages.docgen = pkgs.writeShellScriptBin "docgen" ''
      PATH+=$PATH:${pkgs.nimble}/bin/
      PATH+=$PATH:${pkgs.nim}/bin/
      nimble docgen
    '';
    apps.docgen = {
      type = "app";
      program = "${self'.packages.docgen}/bin/docgen";
    };
    githubActions.workflows.docgen = {
      name = "Docgen";
      on = {
        push.branches = ["main"];
      }; # on
      permissions = {
        id-token = "write";
        pages = "write";
        contents = "write";
      }; # permissions
      jobs = {
        build = {
          name = "Build the documentation";
          runsOn = "ubuntu-latest";
          steps = [
            {uses = "actions/checkout@v7";}
            {uses = "cachix/install-nix-action@v31";}
            {
              name = "Generate documentation";
              id = "build";
              run = "nix run .#docgen";
            }
            {
              name = "Upload documentation";
              id = "deployment";
              uses = "actions/upload-pages-artifact@v3";
              with_ = {
                path = "docs/";
              }; # with_
            }
          ]; # steps
        }; # build
        deploy = {
          name = "Deploy the documentation";
          environment = {
            name = "github-pages";
            url = "\${{ steps.deployment.outputs.page_url }}";
          }; # environment
          runsOn = "ubuntu-latest";
          needs = ["build"];
          steps = [
            {
              name = "deployment";
              id = "deployment";
              uses = "actions/deploy-pages@v4";
            }
          ]; # steps
        }; # deploy
      }; # jobs
    }; # githubActions.workflows.docgen
  }; # perSystem
}
