{pkgs}:
pkgs.writeShellScriptBin "update-ida-pro" ''
  exec ${pkgs.python3}/bin/python3 ${./update.py} "$@"
''
