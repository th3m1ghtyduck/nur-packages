{ pkgs, ... }:
let
  setup = ''
    perl -pi -e 's/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\x74\x11\x48\x8B\x45\xC8\x8B/\x03\x00\x89\x45\xFC\x83\x7D\xFC\x00\xEB\x11\x48\x8B\x45\xC8\x8B/g' $out/bin/resolve
    perl -pi -e 's/\x74\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/\xEB\x11\x48\x8B\x45\xC8\x8B\x55\xFC\x89\x50\x58\xB8\x00\x00\x00/g' $out/bin/resolve
    perl -0777 -pi -e 's/\x74(.\xBF\x16\x00\x00\x00\xBE.\x01\x00\x00\xE8..\x05)/\x75$1/g' $out/bin/resolve
    mkdir -p $out/libs/disabled-libraries
    mv $out/libs/libglib* $out/libs/libgio* $out/libs/libgmodule* $out/libs/disabled-libraries/ 2>/dev/null || true
    mkdir -p $out/.license
    echo 'LICENSE blackmagic davinciresolvestudio 009599 permanent uncounted' > $out/.license/blackmagic.lic
    echo ' hostid=ANY issuer=AHH customer=AHH issued=03-Apr-2024' >> $out/.license/blackmagic.lic
    echo ' akey=3148-9267-1853-4920-8173 _ck=00 sig="00"' >> $out/.license/blackmagic.lic
  '';

  davinci = pkgs.davinci-resolve-studio.davinci.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.perl];
    installPhase = (old.installPhase or "") + setup;
  });

  wrapper = pkgs.writeShellScriptBin "davinci-resolve-studio" ''
    export QT_QPA_PLATFORM=xcb
    exec ${pkgs.davinci-resolve-studio}/bin/davinci-resolve-studio ${davinci}/bin/resolve "$@"
  '';
in
pkgs.symlinkJoin {
  name = "davinci-resolve-studio-personal";
  paths = [pkgs.davinci-resolve-studio];
  postBuild = ''
    rm -f $out/bin/davinci-resolve-studio
    ln -s ${wrapper}/bin/davinci-resolve-studio $out/bin/davinci-resolve-studio
  '';
  passthru = {
    homeFiles = {
      ".local/share/DaVinciResolve/license/blackmagic.lic".text = builtins.concatStringsSep "\n" [
        "LICENSE blackmagic davinciresolvestudio 009599 permanent uncounted"
        " hostid=ANY issuer=AHH customer=AHH issued=03-Apr-2024"
        " akey=3148-9267-1853-4920-8173 _ck=00 sig=\"00\""
      ];
    };
  };
}
