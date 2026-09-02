# This file formats packages in a way that can be built by nix-build.
# e.g.
# nix-build -A mypackage

{ pkgs ? import <nixpkgs> {} }:

{
  binaryninja-personal = pkgs.callPackage ./pkgs/binary-ninja {};
  ida-pro = pkgs.callPackage ./pkgs/ida-pro {};
  davinci-resolve-studio = pkgs.callPackage ./pkgs/davinci-resolve-studio {};
}
