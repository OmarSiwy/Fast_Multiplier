#!/bin/zsh

echo "Generating Golden Reference Files for ASIC Flow"
echo "================================================"
echo ""

RUN_GPK=1
RUN_ADDER=1
RUN_PP=1
RUN_COMPRESSOR=1
RUN_PREFIX=1

# Create asic directory if it doesn't exist
mkdir -p asic

# ======================================
# GPK Golden Generation
# ======================================

if [[ $RUN_GPK -eq 1 ]]; then
  echo "=== Generating GPK Golden Files ==="
  for pipe in 0 1; do
    for dut in gpk; do
      echo "Generating golden for DUT=$dut, PIPE=$pipe"

      # Run make asic command which creates the golden file
      make asic DUT=$dut W=0 M=0 PIPE=$pipe > /dev/null 2>&1

      GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.0.0.${pipe}.rpt"
      if [[ -f $GOLDEN_FILE ]]; then
        echo "  ✓ Created: $GOLDEN_FILE"
      else
        echo "  ✗ Failed to create golden file"
      fi
    done
  done
fi

# ======================================
# Adders Golden Generation
# ======================================

if [[ $RUN_ADDER -eq 1 ]]; then
  echo ""
  echo "=== Generating Adder Golden Files ==="
  for dut in rca csa cla; do
    for w in 4 8 16 32 64; do
      if [[ $dut == rca ]]; then
        m_vals=(0)
      else
        if [[ $w -ge 4 ]]; then
          m_vals=(2 4)
          if [[ $w -ge 16 ]]; then
            m_vals+=(8)
          fi
        fi
      fi

      for m in $m_vals; do
        for pipe in 0 1; do
          echo "Generating golden for DUT=$dut, W=$w, M=$m, PIPE=$pipe"

          # Run make asic command
          make asic DUT=$dut W=$w M=$m PIPE=$pipe > /dev/null 2>&1

          GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.${w}.${m}.${pipe}.rpt"
          if [[ -f $GOLDEN_FILE ]]; then
            echo "  ✓ Created: $GOLDEN_FILE"
          else
            echo "  ✗ Failed to create golden file"
          fi
        done
      done
    done
  done
fi

# ====================================
# Partial Products Golden Generation
# ====================================

if [[ $RUN_PP -eq 1 ]]; then
  echo ""
  echo "=== Generating Partial Products Golden Files ==="
  for w in 4 8 16 32 64; do
    for pipe in 0 1; do
      for dut in binary_pp booth_pp; do
        echo "Generating golden for DUT=$dut, W=$w, PIPE=$pipe"

        # Generate test data and run make asic
        python3 data/generate_${dut}_data.py -w $w -n 128 -o data -r tb > /dev/null 2>&1
        make asic DUT=$dut W=$w M=0 PIPE=$pipe > /dev/null 2>&1

        GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.${w}.0.${pipe}.rpt"
        if [[ -f $GOLDEN_FILE ]]; then
          echo "  ✓ Created: $GOLDEN_FILE"
        else
          echo "  ✗ Failed to create golden file"
        fi
      done
    done
  done
fi

# ======================================
# Compressor Trees Golden Generation
# ======================================

if [[ $RUN_COMPRESSOR -eq 1 ]]; then
  echo ""
  echo "=== Generating Compressor Tree Golden Files ==="
  for w in 4 64; do
    for pipe in 0 1; do
      for alg in dadda bickerstaff faonly; do
        for sign in unsigned signed; do
          for dut in binary booth; do
            # Skip booth unsigned combinations
            if [[ $dut == "booth" && $sign == "unsigned" ]]; then
              continue
            fi

            echo "Generating golden for compressor_tree($dut), W=$w, ALG=$alg, SIGN=$sign, PIPE=$pipe"

            unsigned_val=$([[ $sign == "unsigned" ]] && echo 1 || echo 0)
            booth_val=$([[ $dut == "booth" ]] && echo 1 || echo 0)

            # Generate RTL
            if [[ $sign == "unsigned" ]]; then
              python3 compressor_tree.py -w $w --encoding=$dut --unsigned --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
              python3 data/generate_compressor_tree_data.py -w $w --encoding=$dut --unsigned -n 128 -o data -r tb/top.h > /dev/null 2>&1
            else
              python3 compressor_tree.py -w $w --encoding=$dut --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
              python3 data/generate_compressor_tree_data.py -w $w --encoding=$dut -n 128 -o data -r tb/top.h > /dev/null 2>&1
            fi

            # Run make asic
            make asic DUT=compressor_tree W=$w M=0 PIPE=$pipe UNSIGNED=$unsigned_val ALG=$alg BOOTH=$booth_val > /dev/null 2>&1

            # The makefile creates the golden with standard naming, we need to rename it
            TEMP_GOLDEN="asic/asic-post-par-area.compressor_tree.golden.${w}.0.${pipe}.rpt"
            FINAL_GOLDEN="asic/asic-post-par-area.compressor_tree.${dut}.golden.${w}.${alg}.${sign}.${pipe}.rpt"

            if [[ -f $TEMP_GOLDEN ]]; then
              mv $TEMP_GOLDEN $FINAL_GOLDEN
              echo "  ✓ Created: $FINAL_GOLDEN"
            else
              echo "  ✗ Failed to create golden file"
            fi
          done
        done
      done
    done
  done
fi

# ======================================
# Prefix Tree Golden Generation
# ======================================

if [[ $RUN_PREFIX -eq 1 ]]; then
  echo ""
  echo "=== Generating Prefix Tree Golden Files ==="
  for w in 4 8 16 32 64 128; do
    for pipe in 0 1; do
      for technique in brent-kung sklansky kogge-stone; do
        echo "Generating golden for prefix_tree, W=$w, TECHNIQUE=$technique, PIPE=$pipe"

        # Generate RTL and test data
        python3 prefix_tree.py -w $w --technique=$technique --verilog -o rtl/prefix_tree.sv > /dev/null 2>&1
        python3 data/generate_prefix_cell_data.py -w $w -n 128 -o data -r tb/top.h > /dev/null 2>&1

        # Run make asic
        make asic DUT=prefix_tree W=$w M=0 PIPE=$pipe TECHNIQUE=$technique > /dev/null 2>&1

        # Rename the golden file
        TEMP_GOLDEN="asic/asic-post-par-area.prefix_tree.golden.${w}.0.${pipe}.rpt"
        FINAL_GOLDEN="asic/asic-post-par-area.prefix_tree.golden.${w}.${technique}.${pipe}.rpt"

        if [[ -f $TEMP_GOLDEN ]]; then
          mv $TEMP_GOLDEN $FINAL_GOLDEN
          echo "  ✓ Created: $FINAL_GOLDEN"
        else
          echo "  ✗ Failed to create golden file"
        fi
      done
    done
  done
fi

echo ""
echo "================================================"
echo "Golden file generation complete!"
echo "Total golden files created: $(find asic -name "*.golden.*.rpt" 2>/dev/null | wc -l)"
echo "================================================"
