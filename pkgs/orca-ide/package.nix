# Orca (https://github.com/stablyai/orca), repackaged from upstream's prebuilt
# .deb. Named `orca-ide` -- as upstream itself does on Linux -- because nixpkgs'
# `orca` is the GNOME screen reader.
#
# One derivation for two very different consumers, configured by arguments:
#
#   * a NixOS desktop (packruler/nix-custom): the defaults.
#   * the headless `orca-ide serve` pod image (packruler/containers,
#     orca-runner), which runs with no user namespaces and no_new_privs, so
#     Chromium's sandbox cannot start:
#
#       orca-ide.override {
#         electronFlags = [ "--no-sandbox" ];
#         extraEnv.LIBGL_ALWAYS_SOFTWARE = "1";
#         withOrcaAlias = true;
#       }
#
# Layout, and why it is this shape:
#
#   bin/orca-ide                 the CLI -- upstream's shim, exactly as its deb
#                                symlinks it to /usr/bin/orca-ide.
#   libexec/orca-ide/orca-ide    the app launcher: GApps env, Wayland flags,
#                                `electronFlags`, `extraEnv`. The desktop entry
#                                points here.
#   opt/Orca/orca-ide            Electron itself, deliberately UNWRAPPED.
#
# The shim runs Electron with ELECTRON_RUN_AS_NODE=1, and in that mode any flag
# a wrapper prepends is read by Node as the script path -- so Electron cannot be
# wrapped in place. And when the CLI starts the app (`orca-ide serve`,
# `orca-ide open`) it spawns `process.execPath`, the raw binary, which would
# skip any wrapper and silently drop `--no-sandbox` -- unless
# ORCA_APP_EXECUTABLE is set (upstream src/cli/runtime/launch.ts). So the shim
# itself is patched to default ORCA_APP_EXECUTABLE to the launcher. Patching
# the shim rather than wrapping it also covers the copy Orca's in-app CLI
# installer symlinks into ~/.local/bin, which never passes through bin/.
#
# The deb rather than the AppImage: the AppImage runs inside a buildFHSEnv,
# which needs user namespaces the pod does not have, and it would hide the CLI.
#
# To bump: `node pkgs/orca-ide/update.mjs` -- see that script for details.
{
  lib,
  stdenvNoCC,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeShellWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libGL,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemd,
  vulkan-loader,
  libx11,
  libxcb,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  manifest ? lib.importJSON ./manifest.json,
  # Extra Electron flags for every app launch -- from the desktop entry and
  # from the CLI alike. Never applied to the CLI's own Node-mode process.
  electronFlags ? [ ],
  # Environment variables for the app launcher, as `NAME = "value";`. Each is
  # `--set-default`, so the caller's environment still wins. Embedded in the
  # world-readable nix store: never put a credential here.
  extraEnv ? { },
  # Also install the CLI as `orca`, the name Orca's own docs use. Off by
  # default because on a desktop it would shadow the GNOME screen reader.
  withOrcaAlias ? false,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "orca-ide";
  inherit (manifest) version;

  src = fetchurl {
    url = "https://github.com/stablyai/orca/releases/download/v${finalAttrs.version}/orca-ide_${finalAttrs.version}_amd64.deb";
    hash = "sha512-${manifest.sha512}";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeShellWrapper
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libGL
    libxkbcommon
    nspr
    nss
    pango
    # libudev.so.1 only; the default output would drag in systemd's binaries.
    (lib.getLib systemd)
    vulkan-loader
    # node-pty, sherpa-onnx and the other bundled native binaries link libstdc++.
    stdenv.cc.cc.lib
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
  ];

  # dlopen()ed by Electron at runtime, so autoPatchelf can't see them.
  runtimeDependencies = [
    (lib.getLib systemd)
    libGL
  ];

  # Applied only to the app launcher below.
  dontWrapGApps = true;

  # resources/orcad-template is not run here. It is the runtime Orca uploads
  # to *remote* SSH hosts, one prebuilt tree per target (linux glibc and musl,
  # darwin, win32), and orcad-template.json pins the sha256 of every other
  # file in it. autoPatchelf over the whole output would rewrite those ELF
  # files' interpreter and RPATH to /nix/store paths: the musl ones fail the
  # build outright (no libc.musl to point at), and the glibc ones "succeed"
  # into files that no longer match their pinned hash and would not run on a
  # non-Nix host anyway. So the musl failure must not be silenced with
  # autoPatchelfIgnoreMissingDeps -- that ships the broken glibc copies.
  # autoPatchelf has no exclude, so the automatic pass is off and postFixup
  # runs it over everything else.
  dontAutoPatchelf = true;

  # chrome-sandbox ships in the deb and is left NOT setuid: a store path cannot
  # carry the bit, and under no_new_privs the kernel would ignore it anyway.
  # A desktop falls back to Chromium's user-namespace sandbox; a pod without
  # user namespaces needs `electronFlags = [ "--no-sandbox" ]`.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt $out/bin
    cp -r opt/Orca $out/opt/Orca
    cp -r usr/share $out/share

    shim=$out/opt/Orca/resources/bin/orca-ide
    patchShebangs $shim
    substituteInPlace $shim \
      --replace-fail 'export ORCA_NODE_OPTIONS=' \
        'export ORCA_APP_EXECUTABLE="''${ORCA_APP_EXECUTABLE:-'"$out"'/libexec/orca-ide/orca-ide}"
    export ORCA_NODE_OPTIONS='

    # The shim resolves its own symlink to find the app, so a symlink on PATH
    # works the same as upstream's /usr/bin/orca-ide.
    ln -s $shim $out/bin/orca-ide
    ${lib.optionalString withOrcaAlias "ln -s orca-ide $out/bin/orca"}

    # Exec= is an absolute /opt path upstream; `orca-ide` on PATH is the CLI,
    # not the app, so point at the launcher.
    substituteInPlace $out/share/applications/orca-ide.desktop \
      --replace-fail /opt/Orca/orca-ide $out/libexec/orca-ide/orca-ide

    runHook postInstall
  '';

  # makeShellWrapper, not makeWrapper: wrapGAppsHook3 pulls in
  # makeBinaryWrapper, which takes over makeWrapper and cannot expand the
  # ${NIXOS_OZONE_WL...} flag at runtime -- it passes it through literally.
  postFixup = ''
    # See dontAutoPatchelf above: every file except the orcad-template tree.
    mapfile -d "" patchelfPaths < <(find $out \
      -path $out/opt/Orca/resources/orcad-template -prune -o -type f -print0)
    autoPatchelf --no-recurse -- "''${patchelfPaths[@]}"

    makeShellWrapper $out/opt/Orca/orca-ide $out/libexec/orca-ide/orca-ide \
      "''${gappsWrapperArgs[@]}" \
      ${
        lib.concatStrings (
          lib.mapAttrsToList (
            name: value: "--set-default ${lib.escapeShellArg name} ${lib.escapeShellArg value} \\\n      "
          ) extraEnv
        )
      }${
        lib.optionalString (
          electronFlags != [ ]
        ) "--add-flags ${lib.escapeShellArg (lib.escapeShellArgs electronFlags)} \\\n      "
      }--add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}}"
  '';

  passthru.updateScript = ./update.mjs;

  meta = {
    description = "IDE for working with a fleet of parallel coding agents";
    homepage = "https://onOrca.dev";
    downloadPage = "https://github.com/stablyai/orca/releases";
    changelog = "https://github.com/stablyai/orca/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "orca-ide";
  };
})
