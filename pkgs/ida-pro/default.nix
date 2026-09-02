{pkgs, ...}: let
  srcData = builtins.fromJSON (builtins.readFile ./source.json);
  # Pinned values from source.json
  pinnedTorrentUrl = srcData.torrentUrl;
  pinnedMagnetUrl = srcData.magnetUrl;
  pinnedVersion = srcData.version;
  # Use fakeHash if hash is empty
  pinnedHash =
    if srcData.hash == "" || srcData.hash == null
    then pkgs.lib.fakeHash
    else srcData.hash;

  # Fetch IDA via BitTorrent, at build time try live discovery from hexrays.su first,
  # fallback to pinned URLs from source.json. Uses rqbit (smaller closure than transmission).
  hotfixSrc =
    pkgs.runCommand "ida94hotfix" {
      outputHash = pinnedHash;
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
      nativeBuildInputs = [
        pkgs.rqbit
        pkgs.cacert
        pkgs.curl
        pkgs.gnugrep
        pkgs.gnused
      ];
      # Expose pinned URLs for tooling
      url = pinnedTorrentUrl;
      passthru.magnetUrl = pinnedMagnetUrl;
    } (builtins.readFile ./fetch-torrent.sh);

in
  pkgs.stdenv.mkDerivation {
    pname = "ida-pro";
    version = pinnedVersion;

    src = hotfixSrc;
    dontUnpack = true;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
      pkgs.nodejs
    ];


    buildInputs = [
      pkgs.libGL
      pkgs.glib
      pkgs.fontconfig
      pkgs.freetype
      pkgs.libx11
      pkgs.libXi
      pkgs.libXrender
      pkgs.libXtst
      pkgs.libxcb-image
      pkgs.libxcb-render-util
      pkgs.libxcb-keysyms
      pkgs.libxcb-wm
      pkgs.libxcb-cursor
      pkgs.libxkbcommon
      pkgs.dbus
      pkgs.wayland
      pkgs.libdrm
      pkgs.gtk3
      pkgs.zlib
      pkgs.libxcrypt-legacy
      pkgs.curl
      pkgs.openssl
      pkgs.libsecret
      pkgs.stdenv.cc.cc.lib
      pkgs.python3
    ];

    runtimeDependencies = [
      pkgs.curl
      pkgs.openssl
      pkgs.libsecret
      pkgs.glib
    ];

    appendRunpaths = [
      "${pkgs.lib.getLib pkgs.python3}/lib"
      "${pkgs.lib.getLib pkgs.curl}/lib"
      "${pkgs.lib.getLib pkgs.openssl}/lib"
      "${pkgs.lib.getLib pkgs.libsecret}/lib"
    ];

    dontWrapQtApps = true;
    autoPatchelfIgnoreMissingDeps = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin $out/lib $out/opt
      mkdir -p $out/.local/share/applications

      IDADIR=$out/opt
      HOME=$out

      $(cat $NIX_CC/nix-support/dynamic-linker) $src/ida-pro_*_x64linux.run \
        --mode unattended --prefix $IDADIR --activate_idalib 0

      cp $IDADIR/libida.so $out/lib || true
      addAutoPatchelfSearchPath $IDADIR

      patchelf --add-needed libcrypto.so $IDADIR/libida.so || true

      mv $out/.local/share $out 2>/dev/null || true
      rm -rf $out/.local 2>/dev/null || true
      
      # Patch the generated .desktop file to point to the wrapped executable
      if ls $out/share/applications/com.hex*.desktop 1> /dev/null 2>&1; then
        sed -i 's|^Exec=.*|Exec=ida %F|' $out/share/applications/com.hex*.desktop
      fi

      runHook postInstall
    '';

    postPhases = ["myFinalFixupPhase"];
    myFinalFixupPhase = ''
      echo "Running myFinalFixupPhase"
      for f in $(find $out/opt -type f -name "*.so*" -o -name "ida" -o -name "ida64" -o -name "idat" -o -name "idat64"); do
        if patchelf --print-rpath "$f" >/dev/null 2>&1; then
          RPATH=$(patchelf --print-rpath "$f")
          NEW_RPATH=$(echo "$RPATH" | tr ':' '\n' | grep -v -e "qtbase" -e "qtwayland" | tr '\n' ':' | sed 's/:$//')
          patchelf --set-rpath "$out/opt:$NEW_RPATH" "$f"
        fi
      done
    '';

    postInstall = ''
      ln -sf $out/opt/idapyswitch $out/bin/idapyswitch || true

      if [ -f $out/opt/ida ]; then
        cat <<EOF > $out/bin/ida
      #!/bin/sh
      unset QT_STYLE_OVERRIDE
      export QT_PLUGIN_PATH="$out/opt/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
      $out/opt/idapyswitch --force-path ${pkgs.python3}/lib/libpython3.so >/dev/null 2>&1 || true
      exec $out/opt/ida "\$@"
      EOF
        chmod +x $out/bin/ida
      fi

      if [ -f $out/opt/idat ]; then
        cat <<EOF > $out/bin/idat
      #!/bin/sh
      unset QT_STYLE_OVERRIDE
      export QT_PLUGIN_PATH="$out/opt/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
      exec $out/opt/idat "\$@"
      EOF
        chmod +x $out/bin/idat
      fi

      # Apply hotfix (license + binary patches) from torrent if present
      if [ -d "$out/opt" ] && [ -f "${hotfixSrc}/kg_patch/keygen.js" ]; then
        echo "Applying IDA hotfix patch from ${hotfixSrc}/kg_patch..."
        cp "${hotfixSrc}/kg_patch/keygen.js" "$out/opt/patch.js"
        if [ -f "${hotfixSrc}/kg_patch/idapro.hexlic" ]; then
          cp "${hotfixSrc}/kg_patch/idapro.hexlic" "$out/opt/idapro.hexlic" || true
        fi
        cd "$out/opt"
        node ./patch.js || echo "Warning: patch.js execution failed"
      fi
    '';

    meta = {
      description = "IDA Pro ${pinnedVersion} - Interactive Disassembler and Decompiler";
      homepage = "https://hex-rays.com/ida-pro/";
      license = pkgs.lib.licenses.unfree;
      platforms = ["x86_64-linux"];
      mainProgram = "ida";
    };

    passthru = {
      inherit hotfixSrc;
      torrentUrl = pinnedTorrentUrl;
      magnetUrl = pinnedMagnetUrl;
    };
  }
