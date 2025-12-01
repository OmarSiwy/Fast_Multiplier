{pkgs ? import <nixpkgs> {}}:
pkgs.mkShell {
  name = "multiplier-shell";
  buildInputs = [
    # Simulation
    pkgs.verilator

    # Synthesis
    pkgs.yosys

    # Build tools
    pkgs.gnumake
    pkgs.gcc
    pkgs.pkg-config

    # Python
    pkgs.python312
    pkgs.python312Packages.rich
  ];
  shellHook = ''
    echo "=== Multiplier Development Shell ==="
    echo "  yosys:    $(yosys -V 2>&1 | head -1)"
    echo "  verilator: $(verilator --version)"
    echo ""
  '';
}
