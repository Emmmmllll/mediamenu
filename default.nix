{
  zig_0_14,
  playerctl,
  stdenv,
  gtk3,
  lib,
  zlib,
  pkg-config,
  linkFarm,
  fetchurl,
  runCommandLocal,
  ...
}:
let
  fetchZig = {name, url, hash}: 
    runCommandLocal name {
      nativeBuildInputs = [ zig_0_14 ];
    }
    ''
      hash="$(zig fetch --global-cache-dir "$TMPDIR" ${fetchurl { inherit url hash; }})"
      mv "$TMPDIR/p/$hash" $out
      chmod 755 "$out"
    '';
in
stdenv.mkDerivation rec {
  pname = "media-menu";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    zig_0_14.hook
    pkg-config
  ];

  deps = linkFarm "zig-packages" [
    {
      name = "gobject-0.3.0-Skun7IrmdQHh-PhvmchG9AKnrR2RFS5EhBe5oedb0ITv";
      path = fetchZig {
        name = "gobject";
        url = "https://github.com/ianprime0509/zig-gobject/releases/download/v0.3.0/bindings-gnome47.tar.zst";
        hash = "sha256-IjxpttIA5jztkWr64hW1l6mEa7c5LdEdOa65xdosBSA=";
      };
    }
  ];

  buildInputs = [
    gtk3.dev
    zlib
    playerctl
  ];

  zigBuildFlags = [
    "--system"
    "${deps}"
  ];

  meta = {
    description = "A simple media menu for Linux";
    homepage = "https://github.com/Emmmmllll/mediamenu";
    license = lib.licenses.gpl3Plus;
    mainProgram = "mediamenu";
  };
}