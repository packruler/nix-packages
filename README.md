# nix-packages

Nix packages shared by packruler's NixOS hosts
([`packruler/nix-custom`](https://github.com/packruler/nix-custom)) and container
images ([`packruler/containers`](https://github.com/packruler/containers)), so
each one is packaged once instead of once per consumer.

| Package | What | Bump |
|---|---|---|
| `orca-ide` | [Orca](https://github.com/stablyai/orca), repackaged from the upstream `.deb` | `devbox run bump_orca_ide` |
| `claude-code` | [Claude Code](https://github.com/anthropics/claude-code), vendored from nixpkgs so it can be bumped ahead of a channel | `devbox run bump_claude_code` |

Each bump script passes its arguments through to that package's `update.mjs`
(e.g. `devbox run bump_orca_ide 1.4.218`). `devbox run bump` runs both and
fails if either did.

`.github/workflows/bump.yml` runs both bumps daily and opens a PR for each
change.

## Using it

Apply the overlay to your own nixpkgs, so the packages build against your
channel and not this flake's pin:

```nix
inputs.nix-packages.url = "github:packruler/nix-packages";

# NixOS
nixpkgs.overlays = [ inputs.nix-packages.overlays.default ];

# or a standalone nixpkgs
pkgs = import nixpkgs {
  inherit system;
  overlays = [ nix-packages.overlays.default ];
};
```

`claude-code` is unfree, so the consuming nixpkgs needs
`config.allowUnfree = true` (or an `allowUnfreePredicate` covering it).

### `orca-ide`

- `bin/orca-ide` is the Orca CLI; the desktop entry launches the app.
- For a headless `orca-ide serve` in a pod without user namespaces:

  ```nix
  pkgs.orca-ide.override {
    electronFlags = [ "--no-sandbox" ];
    extraEnv.LIBGL_ALWAYS_SOFTWARE = "1";
    withOrcaAlias = true;
  }
  ```

  This variant is built and checked in CI as `.#orca-ide-headless`. See the
  header of `pkgs/orca-ide/package.nix` for why the package is laid out the way
  it is.

## Checking

```bash
nix flake check -L   # builds every package, asserts the headless layout, checks formatting
nix fmt              # nixfmt over the tree
```
