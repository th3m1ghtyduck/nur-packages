{
  postInstall = ''
    if [ -d "$out/opt/binaryninja" ]; then
      cp ${./setup.py} "$out/opt/binaryninja/script.py"
      cd "$out/opt/binaryninja"
      python3 ./script.py
    fi
  '';
}
