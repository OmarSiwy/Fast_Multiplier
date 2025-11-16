{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "multiplier-shell";

  buildInputs = [
    pkgs.verilator
    pkgs.gnumake
    pkgs.gcc
    pkgs.pkg-config
    (pkgs.python3.withPackages (ps: with ps; [rich]))
  ];

  shellHook = ''
  '';
}
