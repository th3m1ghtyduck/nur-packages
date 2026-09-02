{ pkgs, ... }:
let
  patch = builtins.readFile ./patch.sh;

  davinci = pkgs.davinci-resolve-studio.davinci.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.perl];
    installPhase = (old.installPhase or "") + patch;
  });

  wrapper = pkgs.writeShellScriptBin "davinci-resolve-studio" ''
    export QT_QPA_PLATFORM=xcb
    exec ${pkgs.davinci-resolve-studio}/bin/davinci-resolve-studio ${davinci}/bin/resolve "$@"
  '';
in
pkgs.symlinkJoin {
  name = "davinci-resolve-studio";
  paths = [pkgs.davinci-resolve-studio];
  postBuild = ''
    rm -f $out/bin/davinci-resolve-studio
    ln -s ${wrapper}/bin/davinci-resolve-studio $out/bin/davinci-resolve-studio
  '';
}
