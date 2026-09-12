{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    packages = {
      tag = pkgs.writeShellScriptBin "tag" ''
        PATH+=$PATH:${pkgs.nimble}/bin/
        PATH+=$PATH:${pkgs.nim}/bin/
        nimble tag
      '';
      docgen = pkgs.writeShellScriptBin "docgen" ''
        PATH+=$PATH:${pkgs.nimble}/bin/
        PATH+=$PATH:${pkgs.nim}/bin/
        nimble docgen
      '';
    }; # packages
    apps = {
      tag = {
        type = "app";
        program = "${self'.packages.tag}/bin/tag";
      };
      docgen = {
        type = "app";
        program = "${self'.packages.docgen}/bin/docgen";
      };
    }; # apps
    githubActions.workflows.td = {
      name = "Tag & Document";
      on.workflowRun = {
        workflows = ["test"];
        types = ["completed"];
        branches = ["dev"];
      }; # on.workflowRun
      permissions = {
        id-token = "write";
        pages = "write";
        contents = "write";
      }; # permissions
    }; # githubActions.workflows.ttd
    githubActions.workflows.td.jobs = {
     tag = {
        name = "Merge into main and tag the commit";
        runsOn = "ubuntu-latest";
        env = {
          "GH_TOKEN" = "\${{ secrets.GITHUB_TOKEN }}";
        }; # env
        steps = [
          {
            uses = "actions/checkout@v7";
            with_.fetch-depth = "0";
          }
          {uses = "cachix/install-nix-action@v31";}
          {
            name = "Run the Tag script";
            id = "run";
            run = ''
              git config user.name "Carmelo Augusto Maita Orlando"
              git config user.email "98987672+CarmeloMaitaO@users.noreply.github.com"
              git checkout dev
              git pull
              nix run .#tag
              version=$(<version)
              echo "THE VERSION IN DEV IS:" $version
              git checkout main
              git pull
              git merge origin/dev
              git push
              git tag $version
              git push --tags
            '';
          }
        ]; # steps
      }; # tag
      doc = {
        name = "Document & deploy";
        runsOn = "ubuntu-latest";
        env = {
          "GH_TOKEN" = "\${{ secrets.GITHUB_TOKEN }}";
        }; # env
        needs = ["tag"];
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
