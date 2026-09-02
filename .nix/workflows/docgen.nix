{self, inputs, ...}: {
  perSystem = {pkgs, config, ...}: {
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
            {uses = "actions/checkout@v4";}
            {uses = "DeterminateSystems/determinate-nix-action@v3";}
            {
              name = "Launch devshell";
              run = "nix develop";
            }
            {
              name = "Generate documentation";
              id = "build";
              run = "nimble docgen";
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
