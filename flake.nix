{
  description = "Nix packages shared by packruler's NixOS hosts and container images";

  # Used only for this repo's own checks and `nix build`. Consumers apply
  # overlays.default to their own nixpkgs instead -- see ./overlay.nix.
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # claude-code is unfree; orca-ide is MIT.
        config.allowUnfree = true;
        overlays = [ self.overlays.default ];
      };

      # The configuration packruler/containers' orca-runner image uses. Built
      # here too so a change that only breaks the headless variant fails in
      # this repo rather than in the image build.
      orca-ide-headless = pkgs.orca-ide.override {
        electronFlags = [ "--no-sandbox" ];
        extraEnv.LIBGL_ALWAYS_SOFTWARE = "1";
        withOrcaAlias = true;
      };
    in
    {
      overlays.default = import ./overlay.nix;

      packages.${system} = {
        inherit (pkgs) claude-code orca-ide;
        inherit orca-ide-headless;
      };

      checks.${system} = {
        inherit (pkgs) claude-code orca-ide;
        inherit orca-ide-headless;

        # The two properties the headless variant exists for, asserted on the
        # built output: the CLI shim hands app launches to the launcher, and
        # the launcher carries --no-sandbox. Either one missing is a pod that
        # crash-loops on Chromium's sandbox.
        orca-ide-headless-layout = pkgs.runCommand "orca-ide-headless-layout" { } ''
          shim=${orca-ide-headless}/opt/Orca/resources/bin/orca-ide
          launcher=${orca-ide-headless}/libexec/orca-ide/orca-ide
          grep -F 'ORCA_APP_EXECUTABLE="''${ORCA_APP_EXECUTABLE:-${orca-ide-headless}/libexec/orca-ide/orca-ide}"' $shim
          grep -F -- '--no-sandbox' $launcher
          grep -F 'LIBGL_ALWAYS_SOFTWARE' $launcher
          test "$(readlink ${orca-ide-headless}/bin/orca)" = orca-ide
          touch $out
        '';

        formatting = pkgs.runCommand "formatting" { nativeBuildInputs = [ pkgs.nixfmt-tree ]; } ''
          cp -r ${self} src
          chmod -R u+w src
          cd src
          HOME=$TMPDIR treefmt --ci
          touch $out
        '';
      };

      formatter.${system} = pkgs.nixfmt-tree;
    };
}
