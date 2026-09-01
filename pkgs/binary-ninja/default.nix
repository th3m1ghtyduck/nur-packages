{ pkgs, ... }:
let
  setupExists = builtins.pathExists ./setup;
  setupDir = ./setup;
  srcData = builtins.fromJSON (builtins.readFile ./source.json);
  binjaZip = pkgs.requireFile {
    name = "binaryninja_linux_${srcData.version}_personal.zip";
    url = "https://binary.ninja";
    sha256 = srcData.hash;
  };
in
pkgs.binary-ninja-personal-wayland.overrideAttrs (old: {
  src = binjaZip;

  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.python312 pkgs.python312Packages.pycryptodome pkgs.makeWrapper ];

  autoPatchelfIgnoreMissingDeps = (old.autoPatchelfIgnoreMissingDeps or []) ++ [
    "libQt6WaylandEglClientHwIntegration.so.6"
  ];

  postInstall = (old.postInstall or "") + (
    if setupExists then (import setupDir).postInstall else ""
  );

  postFixup = (old.postFixup or "") + ''
    if [ -f "$out/bin/binaryninja" ]; then
      wrapProgram "$out/bin/binaryninja" \
        --set-default PYTHON ${pkgs.python312}/bin/python3 \
        --prefix PATH : ${pkgs.python312}/bin \
        --prefix PYTHONPATH : "\$BINJA_PYTHONPATH"
    fi

    if [ -f "$out/share/applications/Binary Ninja.desktop" ]; then
      sed -i 's|^Icon=.*|Icon='"$out"'/share/pixmaps/binaryninja.png|' "$out/share/applications/Binary Ninja.desktop"
    fi
  '';
})
