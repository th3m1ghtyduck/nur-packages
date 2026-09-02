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

# Flatten, if torrent contained a single top-level directory, move its contents to $out
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
