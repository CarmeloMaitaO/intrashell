{self, inputs, ...}: {
  perSystem = {self', pkgs, config, ...}: {
    githubActions.workflows.tag = {
      name = "Tag";
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
              uses = "actions/checkout@v7";
              with_ = {
                fetch-depth = "0";
              };
            }
            {
              name = "Run the Tag script";
              id = "run";
              with_ = {
                GH_TOKEN = "\${{ secrets.GITHUB_TOKEN }}"
              };
              run = ''
                version=$(<version)
                git config user.name "Git Bot"
                git config user.email "carmeloaugustomaitaorlando@gmail.com"
                git checkout main
                git pull
                git fetch --all
                git merge development
                git push
                git tag $version
                git push --tags
              '';
            }
          ]; # steps
        }; # tag
      }; # jobs
    }; # githubActions.workflows.docgen
  }; # perSystem
}
