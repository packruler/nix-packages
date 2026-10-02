# The one way consumers should take these packages: as an overlay, so each
# builds them against its OWN nixpkgs rather than this flake's pin.
# packruler/nix-custom is on a stable release and packruler/containers on
# unstable; neither should be dragged onto a third nixpkgs by depending on this.
final: _prev: {
  claude-code = final.callPackage ./pkgs/claude-code/package.nix { };
  orca-ide = final.callPackage ./pkgs/orca-ide/package.nix { };
}
