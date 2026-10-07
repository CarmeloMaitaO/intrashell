{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages = {
      docgen = pkgs.writeShellScriptBin "docgen" ''
        PATH+=$PATH:${pkgs.nimble}/bin/
        PATH+=$PATH:${pkgs.nim}/bin/
        nimble docgen
      '';
    }; # packages
    apps = {
      docgen = {
        type = "app";
        program = "${self'.packages.docgen}/bin/docgen";
      };
    }; # apps
    githubActions.workflows.td = {
      name = "Tag & Document";
      on.push = {
        tags = ["*"];
      }; # on.push
      permissions = {
        id-token = "write";
        pages = "write";
        contents = "write";
      }; # permissions
    }; # githubActions.workflows.ttd
    githubActions.workflows.td.jobs = {
      doc = {
        name = "Document & deploy";
        runsOn = "ubuntu-latest";
        env = {
          "GH_TOKEN" = "\${{ secrets.GITHUB_TOKEN }}";
        }; # env
        environment = {
          name = "github-pages";
          url = "\${{ steps.deployment.outputs.page_url }}";
        }; # environment
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
          {
            name = "deployment";
            uses = "actions/deploy-pages@v4";
          }
        ];
      }; # doc
    }; # githubActions.workflows.td.jobs
  }; # perSystem
}
