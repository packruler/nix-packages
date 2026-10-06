# Vendored from nixpkgs `pkgs/by-name/cl/claude-code/package.nix` at rev
# 8c3cede7ddc26bd659d2d383b5610efbd2c7a16e (nixos-26.05 at the time), so that
# the version can be bumped here instead of waiting on a channel bump.
#
# Kept deliberately close to the upstream file so a future `diff` against
# nixpkgs stays meaningful. The only intentional divergences are:
#   * `manifest` is a function argument rather than a `let` binding, so the pin
#     lives in ./manifest.json and callers can `.override { manifest = ...; }`.
#   * `extraEnv` adds `--set` flags to the wrapper so non-secret environment
#     variables can be configured from Nix (see the comment on the argument).
#   * `envFiles` puts a shell script in front of the wrapper that sources
#     dotenv files at runtime, for variables that are secret (see the comment
#     on the argument).
#   * `meta.maintainers` is dropped -- the nixpkgs maintainers do not maintain
#     this copy.
#   * `passthru.updateScript` points at ./update.mjs rather than nixpkgs'
#     ./update.sh, which depends on the nixpkgs update harness.
#
# To bump: `node pkgs/claude-code/update.mjs` — see that script for details.
{
  lib,
  stdenvNoCC,
  fetchurl,
  installShellFiles,
  makeBinaryWrapper,
  autoPatchelfHook,
  alsa-lib,
  procps,
  ripgrep,
  bubblewrap,
  socat,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  manifest ? lib.importJSON ./manifest.json,
  # Non-secret environment variables to bake into the wrapper, as an attrset of
  # `NAME = "value";`. Each becomes a `--set` flag, which is a flag
  # `makeBinaryWrapper` actually supports -- unlike `--run`, which is
  # `makeWrapper`-only and made the previous `envFile` argument fail to build.
  #
  # Applied AFTER the defaults below, so a caller can override one of them
  # (e.g. USE_BUILTIN_RIPGREP) rather than being stuck with it.
  #
  # Values are embedded in the wrapper in the WORLD-READABLE nix store, so never
  # put a credential here. claude-code authenticates via claude.ai on these
  # machines; if it ever needs a real secret, use its own
  # `ANTHROPIC_IDENTITY_TOKEN_FILE` / `apiKeyHelper` mechanisms, which read a
  # path at runtime, instead of this argument.
  extraEnv ? { },
  # Runtime paths of dotenv-style files (e.g. an agenix secret under
  # /run/agenix) to source before starting claude-code, for variables that must
  # NOT land in the nix store -- an OTLP exporter's auth header, say. Each file
  # is sourced with `set -a`, so plain `NAME=value` lines are exported too; a
  # file that is missing or unreadable is skipped silently.
  #
  # makeBinaryWrapper cannot run shell code, so a non-empty list adds a small
  # shell script in front of the binary wrapper. The files are sourced first,
  # so the wrapper's own `--set` flags (the defaults and `extraEnv`) still win.
  #
  # Must be strings: a Nix path literal (./foo.env) would be copied into the
  # world-readable store, which defeats the point -- hence the assertion below.
  envFiles ? [ ],
  runtimeShell,
}:
assert lib.assertMsg (lib.all builtins.isString envFiles)
  "claude-code: envFiles must be runtime path strings, not Nix paths (which would copy the file into the nix store)";
let
  stdenv = stdenvNoCC;
  baseUrl = "https://downloads.claude.ai/claude-code-releases";
  platformKey = "${stdenv.hostPlatform.node.platform}-${stdenv.hostPlatform.node.arch}";
  platformManifestEntry = manifest.platforms.${platformKey};
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-code";
  inherit (manifest) version;

  src = fetchurl {
    url = "${baseUrl}/${finalAttrs.version}/${platformKey}/claude";
    sha256 = platformManifestEntry.checksum;
  };

  dontUnpack = true;
  dontBuild = true;
  __noChroot = stdenv.hostPlatform.isDarwin;
  # otherwise the bun runtime is executed instead of the binary
  dontStrip = true;

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];

  strictDeps = true;

  installPhase = ''
    runHook preInstall

    installBin $src

    wrapProgram $out/bin/claude \
      --set DISABLE_AUTOUPDATER 1 \
      --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
      --set DISABLE_INSTALLATION_CHECKS 1 \
      --set USE_BUILTIN_RIPGREP 0 \
      ${
        lib.concatStrings (
          lib.mapAttrsToList (
            name: value: "--set ${lib.escapeShellArg name} ${lib.escapeShellArg value} \\\n      "
          ) extraEnv
        )
      }${lib.optionalString stdenv.hostPlatform.isLinux ''
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ alsa-lib ]} \
      ''}--prefix PATH : ${
        lib.makeBinPath (
          [
            # claude-code uses [node-tree-kill](https://github.com/pkrumins/node-tree-kill) which requires procps's pgrep(darwin) or ps(linux)
            procps
            # https://code.claude.com/docs/en/troubleshooting#search-and-discovery-issues
            ripgrep
          ]
          # the following packages are required for the sandbox to work (Linux only)
          ++ lib.optionals stdenv.hostPlatform.isLinux [
            bubblewrap
            socat
          ]
        )
      }
  ''
  + lib.optionalString (envFiles != [ ]) ''
    mv $out/bin/claude $out/bin/.claude-env-wrapped
    cat > $out/bin/claude <<'EOF'
    #!${runtimeShell}
    set -a
    ${
      lib.concatMapStrings (
        file: "if [ -r ${lib.escapeShellArg file} ]; then . ${lib.escapeShellArg file}; fi\n"
      ) envFiles
    }set +a
    exec -a "$0" ${placeholder "out"}/bin/.claude-env-wrapped "$@"
    EOF
    chmod +x $out/bin/claude
  ''
  + ''

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckKeepEnvironment = [ "HOME" ];
  versionCheckProgramArg = "--version";

  passthru.updateScript = ./update.mjs;

  meta = {
    description = "Agentic coding tool that lives in your terminal, understands your codebase, and helps you code faster";
    homepage = "https://github.com/anthropics/claude-code";
    downloadPage = "https://claude.com/product/claude-code";
    changelog = "https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md";
    license = lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
      "aarch64-linux"
      "x86_64-linux"
    ];
    mainProgram = "claude";
  };
})
