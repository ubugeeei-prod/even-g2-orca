# Deployable tree: web/ (phone app), worker/ (Cloudflare Worker), bridge/ (Mac).
{
  lib,
  stdenvNoCC,
  fetchurl,
  moonbit,
  sdk,
}:
let
  evenHubSdk = fetchurl {
    url = sdk.EVEN_HUB_SDK_URL;
    hash = sdk.EVEN_HUB_SDK_INTEGRITY;
  };
in
stdenvNoCC.mkDerivation {
  pname = "even-g2-orca";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../moon.mod
      ../core
      ../js
      ../app
      ../bridge
      ../worker
      ../web
      ../scripts
    ];
  };

  nativeBuildInputs = [ moonbit ];

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR" MOON_HOME="$TMPDIR/.moon"
    tar -xzf ${evenHubSdk} package/dist/index.js package/LICENSE
    EVEN_HUB_SDK="$PWD/package/dist/index.js" bash scripts/build.sh "$out"
    cp package/LICENSE "$out/web/even_hub_sdk.LICENSE"
    runHook postBuild
  '';

  dontInstall = true;

  meta = {
    description = "Operate Orca coding agents from Even G2 glasses";
    platforms = moonbit.meta.platforms;
  };
}
