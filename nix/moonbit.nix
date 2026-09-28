# The MoonBit toolchain from the official prebuilt artifacts pinned in
# moonbit.lock.json. The standard library ships as source; it is bundled for
# the JS backend here so every build uses the same, cached core.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
  makeWrapper,
  autoPatchelfHook ? null,
  lock,
}:
let
  system = stdenv.hostPlatform.system;
  spec =
    lock.moonbit.platforms.${system}
      or (throw "MoonBit is not pinned for ${system}; add it to nix/moonbit.lock.json");
  toolchain = fetchurl {
    url = "${lock.moonbit.baseUrl}/${spec.asset}";
    hash = spec.hash;
  };
  core = fetchurl {
    url = lock.moonbit.coreUrl;
    hash = lock.moonbit.coreHash;
  };
  executables = [
    "moon"
    "moonc"
    "moonrun"
    "moonfmt"
    "mooninfo"
    "moondoc"
    "mooncake"
    "moon-lsp"
    "moon-ide"
  ];
in
stdenv.mkDerivation {
  pname = "moonbit";
  version = lock.moonbit.version;
  srcs = [
    toolchain
    core
  ];

  nativeBuildInputs = [
    unzip
    makeWrapper
  ]
  ++ lib.optional (stdenv.hostPlatform.isLinux && autoPatchelfHook != null) autoPatchelfHook;

  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  unpackPhase = ''
    runHook preUnpack
    mkdir -p toolchain
    tar -xzf ${toolchain} -C toolchain
    unzip -q ${core} -d toolchain/lib
    runHook postUnpack
  '';

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    chmod -R u+w toolchain
    chmod +x toolchain/bin/* || true
    export MOON_TOOLCHAIN_ROOT="$PWD/toolchain"
    export PATH="$PWD/toolchain/bin:$PATH"
    export HOME="$TMPDIR"
    ${lib.optionalString stdenv.hostPlatform.isLinux ''autoPatchelf toolchain/bin''}
    moon -C toolchain/lib/core bundle --all --target js
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec" "$out/bin"
    cp -r toolchain/lib toolchain/include "$out/" 2>/dev/null || true
    cp -r toolchain/bin/* "$out/libexec/"
    for exe in ${lib.escapeShellArgs executables}; do
      if [ -f "$out/libexec/$exe" ]; then
        makeWrapper "$out/libexec/$exe" "$out/bin/$exe" \
          --set-default MOON_TOOLCHAIN_ROOT "$out"
      fi
    done
    runHook postInstall
  '';

  dontStrip = true;
  dontPatchELF = stdenv.hostPlatform.isDarwin;

  meta = {
    description = "MoonBit toolchain (JS backend core bundled)";
    homepage = "https://www.moonbitlang.com/";
    license = lib.licenses.unfreeRedistributable;
    platforms = builtins.attrNames lock.moonbit.platforms;
    mainProgram = "moon";
  };
}
