{self, inputs, ...}: {
  perSystem = {pkgs, config, ...}: {
    githubActions = {
      enable = true;
    };
    packages.workflows = pkgs.writeShellScriptBin "copy-workflows" ''
      mkdir -p ./.github/workflows
      cp -r ${config.githubActions.workflowsDir}/* ./.github/workflows/
      chmod -R ugo+rw ./.github
    '';
  }; # perSystem
}
