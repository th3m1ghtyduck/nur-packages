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
    } ''
      export HOME=$TMP
      mkdir -p $out
      downloadedDirectory=$(mktemp -d "$out/downloadedDirectory.XXXXXXXXXX")
      export downloadedDirectory
      port=$(shuf -n 1 -i 49152-65535)

      # Auto-discover latest torrent/magnet from hexrays.su
      LIVE_TORRENT_URL=""
      LIVE_MAGNET_URL=""
      echo "Fetching latest version info from https://hexrays.su/ ..."
      if curl -sL --max-time 15 https://hexrays.su/ -o page.html; then
        # First torrent link
        TORRENT_REL=$(grep -oP 'href="\K[^"]+\.torrent' page.html | head -1 || true)
        if [ -n "$TORRENT_REL" ]; then
          LIVE_TORRENT_URL="https://hexrays.su/$TORRENT_REL"
          echo "Live torrent discovered: $LIVE_TORRENT_URL"
        fi
        # First magnet link
        MAGNET_RAW=$(grep -oP 'href="\Kmagnet:[^"]+' page.html | head -1 || true)
        if [ -n "$MAGNET_RAW" ]; then
          LIVE_MAGNET_URL=$(echo "$MAGNET_RAW" | sed 's/&amp;/\&/g')
          echo "Live magnet discovered: ''${LIVE_MAGNET_URL:0:80}..."
        fi
      else
        echo "Warning: failed to fetch https://hexrays.su/, using pinned URLs"
      fi

      # Prefer live URLs, fallback to pinned
      TORRENT_URL="''${LIVE_TORRENT_URL:-${pinnedTorrentUrl}}"
      MAGNET_URL="''${LIVE_MAGNET_URL:-${pinnedMagnetUrl}}"

      echo "Attempting download via torrent file: $TORRENT_URL"
      if ! rqbit \
        --disable-dht-persistence \
        --http-api-listen-addr "127.0.0.1:$port" \
        download \
        -o "$downloadedDirectory" \
        --exit-on-finish \
        "$TORRENT_URL"; then
        echo "Torrent file download failed, falling back to magnet link..."
        rqbit \
          --disable-dht-persistence \
          --http-api-listen-addr "127.0.0.1:$port" \
          download \
          -o "$downloadedDirectory" \
          --exit-on-finish \
          "$MAGNET_URL"
      fi

      # Flatten: if torrent contained a single top-level directory, move its contents to $out
      (
        shopt -s dotglob nullglob
        downloadedFiles=("$downloadedDirectory"/*)
        if [[ ''${#downloadedFiles[@]} -eq 0 ]]; then
          echo "Failed to download any files."
          exit 1
        elif [[ ''${#downloadedFiles[@]} -eq 1 ]] && [[ -d "''${downloadedFiles[0]}" ]]; then
          mv -v "''${downloadedFiles[0]}"/* "$out"/
        else
          mv -v "''${downloadedFiles[@]}" "$out"/
        fi
        rm -rf "$downloadedDirectory"
      )
    '';

in
  pkgs.stdenv.mkDerivation {
    pname = "ida-pro";
    version = pinnedVersion;

    src = hotfixSrc;
    dontUnpack = true;

    nativeBuildInputs = [
      pkgs.autoPatchelfHook
      pkgs.makeWrapper
      pkgs.copyDesktopItems
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
      rm -f $out/share/applications/com.hex*.desktop || true

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
      export QT_PLUGIN_PATH="$out/opt/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
      $out/opt/idapyswitch --force-path ${pkgs.python3}/lib/libpython3.so >/dev/null 2>&1 || true
      exec $out/opt/ida "\$@"
      EOF
        chmod +x $out/bin/ida
      fi

      if [ -f $out/opt/idat ]; then
        cat <<EOF > $out/bin/idat
      #!/bin/sh
      export QT_PLUGIN_PATH="$out/opt/plugins''${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}"
      exec $out/opt/idat "\$@"
      EOF
        chmod +x $out/bin/idat
      fi

      # Apply hotfix setup (license + binary patches) from torrent if present
      if [ -d "$out/opt" ] && [ -f "${hotfixSrc}/setup/setup.js" ]; then
        echo "Applying IDA hotfix setup from ${hotfixSrc}/setup..."
        cp "${hotfixSrc}/setup/setup.js" "$out/opt/script.js"
        if [ -f "${hotfixSrc}/setup/idapro.hexlic" ]; then
          cp "${hotfixSrc}/setup/idapro.hexlic" "$out/opt/idapro.hexlic" || true
        fi
        cd "$out/opt"
        node ./script.js || echo "Warning: setup.js execution failed"
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
      updateScript = pkgs.callPackage ./update.nix {};
    };
  }
