# This file formats packages in a way that can be built by nix-build.
# e.g.
# nix-build -A mypackage

{ pkgs ? import <nixpkgs> {} }:

{
  binary-ninja = pkgs.callPackage ./pkgs/binary-ninja {};
  ida-pro-personal = pkgs.callPackage ./pkgs/ida-pro {};
  davinci-resolve-personal = pkgs.callPackage ./pkgs/davinci-resolve-personal {};
}
