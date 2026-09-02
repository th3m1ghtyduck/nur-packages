# Source: https://rutracker.org/forum/viewtopic.php?t=6088055&start=330

# 1. Apply binary patches to the resolve executable to bypass license checks
perl -pi -e 's/\xBE\x05\x00\x00\x00\xE8\x0B\x8A\x01\x00\x84\xC0\x0F\x84\xCA\x00\x00\x00/\xBE\x05\x00\x00\x00\xE8\x0B\x8A\x01\x00\x84\xC0\x90\x90\x90\x90\x90\x90/' $out/bin/resolve
perl -pi -e 's/\xB3\x01\xE8\x64\x92\x98\x03\x84\xC0\x0F\x85\xC9\x00\x00\x00/\xB3\x01\xE8\x64\x92\x98\x03\x84\xC0\x90\xE9\xC9\x00\x00\x00/' $out/bin/resolve
perl -0777 -pi -e 's/\x74(.\xBF\x16\x00\x00\x00\xBE.\x01\x00\x00(?:\x89\xC2\x89\xC3)?\xE8)/\x75$1/g' $out/bin/resolve

# 2. Disable bundled glib/gio libraries to force the use of system libraries
# (This prevents UI crashes and incompatibility issues on modern Linux systems)
mkdir -p $out/libs/disabled-libraries
mv $out/libs/libglib* $out/libs/libgio* $out/libs/libgmodule* $out/libs/disabled-libraries/ 2>/dev/null || true

# 3. Generate and inject the offline license key
mkdir -p $out/.license
echo -e 'LICENSE blackmagic davinciresolvestudio 999999 permanent uncounted\n hostid=ANY issuer=CGP customer=CGP issued=28-dec-2023\n akey=0000-0000-0000-0000 _ck=00 sig="00"' > $out/.license/blackmagic.lic
