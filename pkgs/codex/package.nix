# OpenAI Codex CLI, repackaged from upstream's prebuilt release bundle rather
# than built from source like nixpkgs' `codex`, so it can be bumped the same
# day as a release instead of waiting on a channel (nixpkgs trails upstream by
# several versions, and a source build means cargo + V8 per bump).
#
# The bundle is `codex-package-<target>.tar.gz`, the same layout upstream's
# install.sh lays down: `bin/codex` plus its companions (`codex-exec-server`,
# `codex-code-mode-host`), a bundled `rg` under `codex-path/`, and `bwrap` and
# the voice runtime under `codex-resources/`. codex finds those relative to its
# own executable, so the tree is installed whole under libexec/codex and
# bin/codex is a wrapper pointing into it.
#
# The Linux targets are musl static-pie, so the main binaries need no patching.
# The one dynamic binary is the optional voice host (glibc), which
# autoPatchelfHook points at the libs bundled beside it.
#
# To bump: `node pkgs/codex/update.mjs` -- see that script for details.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  manifest ? lib.importJSON ./manifest.json,
  # Non-secret environment variables to bake into the wrapper, as an attrset of
  # `NAME = "value";`. Same contract as claude-code's argument: values land in
  # the world-readable nix store, so never put a credential here.
  extraEnv ? { },
}:
let
  stdenv = stdenvNoCC;
  platform =
    manifest.platforms.${stdenv.hostPlatform.system}
      or (throw "codex: no prebuilt bundle pinned for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "codex";
  inherit (manifest) version;

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${finalAttrs.version}/codex-package-${platform.target}.tar.gz";
    sha256 = platform.sha256;
  };

  sourceRoot = ".";
  dontBuild = true;
  dontConfigure = true;
  # Upstream ships these stripped already; stripping again gains nothing and
  # risks the static-pie binaries.
  dontStrip = true;

  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isElf [ autoPatchelfHook ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/codex
    cp -r bin codex-path codex-resources codex-package.json $out/libexec/codex/
    ${lib.optionalString stdenv.hostPlatform.isElf ''
      if [ -d $out/libexec/codex/codex-resources/voice/lib ]; then
        addAutoPatchelfSearchPath $out/libexec/codex/codex-resources/voice/lib
      fi
    ''}

    makeWrapper $out/libexec/codex/bin/codex $out/bin/codex \
      ${
        lib.concatStrings (
          lib.mapAttrsToList (
            name: value: "--set ${lib.escapeShellArg name} ${lib.escapeShellArg value} \\\n      "
          ) extraEnv
        )
      }--prefix PATH : $out/libexec/codex/codex-path

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
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = builtins.attrNames manifest.platforms;
    mainProgram = "codex";
  };
})
