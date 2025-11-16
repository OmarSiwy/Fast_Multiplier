#!/bin/zsh

echo "" > grade_asic.log

RUN_GPK=1
RUN_ADDER=1
RUN_PP=1
RUN_COMPRESSOR=1
RUN_PREFIX=1

# Function to compare ASIC metrics
compare_asic_metrics() {
  local result_file=$1
  local golden_file=$2
  local log_prefix=$3

  # Check if both files exist
  if [[ ! -f $result_file ]]; then
    echo "${log_prefix},STATUS=MISSING_RESULT_FILE" >> grade_asic.log
    echo "GRADE,0" >> grade_asic.log
    return 1
  fi

  if [[ ! -f $golden_file ]]; then
    echo "${log_prefix},STATUS=MISSING_GOLDEN_FILE" >> grade_asic.log
    echo "GRADE,0" >> grade_asic.log
    return 1
  fi

  # Extract metrics from result file (Area, Delay, Power)
  RESULT_AREA=$(grep -i "Total cell area:" $result_file | awk '{print $4}')
  RESULT_DELAY=$(grep -i "slack" $result_file | grep -i "MET\|VIOLATED" | head -1 | awk '{print $(NF-1)}' | tr -d '()')
  RESULT_POWER=$(grep -i "^Total" $result_file | grep -i "power" | awk '{print $NF}')

  # Extract metrics from golden file
  GOLDEN_AREA=$(grep -i "Total cell area:" $golden_file | awk '{print $4}')
  GOLDEN_DELAY=$(grep -i "slack" $golden_file | grep -i "MET\|VIOLATED" | head -1 | awk '{print $(NF-1)}' | tr -d '()')
  GOLDEN_POWER=$(grep -i "^Total" $golden_file | grep -i "power" | awk '{print $NF}')

  # Check if metrics were extracted
  if [[ -z $RESULT_AREA || -z $RESULT_DELAY || -z $RESULT_POWER ]]; then
    echo "${log_prefix},STATUS=FAILED_TO_EXTRACT_RESULT_METRICS" >> grade_asic.log
    echo "GRADE,0" >> grade_asic.log
    return 1
  fi

  if [[ -z $GOLDEN_AREA || -z $GOLDEN_DELAY || -z $GOLDEN_POWER ]]; then
    echo "${log_prefix},STATUS=FAILED_TO_EXTRACT_GOLDEN_METRICS" >> grade_asic.log
    echo "GRADE,0" >> grade_asic.log
    return 1
  fi

  # Compare metrics (allow 5% tolerance)
  TOLERANCE=5.0

  # Calculate percentage differences
  AREA_DIFF=$(python3 -c "print(abs(($RESULT_AREA - $GOLDEN_AREA) / $GOLDEN_AREA * 100) if $GOLDEN_AREA != 0 else 0)")
  DELAY_DIFF=$(python3 -c "print(abs(($RESULT_DELAY - $GOLDEN_DELAY) / abs($GOLDEN_DELAY) * 100) if $GOLDEN_DELAY != 0 else 0)")
  POWER_DIFF=$(python3 -c "print(abs(($RESULT_POWER - $GOLDEN_POWER) / $GOLDEN_POWER * 100) if $GOLDEN_POWER != 0 else 0)")

  # Check if within tolerance
  AREA_PASS=$(python3 -c "print(1 if $AREA_DIFF <= $TOLERANCE else 0)")
  DELAY_PASS=$(python3 -c "print(1 if $DELAY_DIFF <= $TOLERANCE else 0)")
  POWER_PASS=$(python3 -c "print(1 if $POWER_DIFF <= $TOLERANCE else 0)")

  # Overall pass if all metrics pass
  if [[ $AREA_PASS -eq 1 && $DELAY_PASS -eq 1 && $POWER_PASS -eq 1 ]]; then
    PASS=1
    STATUS="PASS"
  else
    PASS=0
    STATUS="FAIL"
  fi

  # Log results
  echo "${log_prefix},STATUS=$STATUS,AREA_DIFF=${AREA_DIFF}%,DELAY_DIFF=${DELAY_DIFF}%,POWER_DIFF=${POWER_DIFF}%" >> grade_asic.log
  echo "  Result: Area=$RESULT_AREA, Delay=$RESULT_DELAY, Power=$RESULT_POWER" >> grade_asic.log
  echo "  Golden: Area=$GOLDEN_AREA, Delay=$GOLDEN_DELAY, Power=$GOLDEN_POWER" >> grade_asic.log
  echo "GRADE,$PASS" >> grade_asic.log

  return 0
}

# ======================================
# GPK ASIC Testing
# ======================================

if [[ $RUN_GPK -eq 1 ]]; then
  for pipe in 0 1; do
    for dut in gpk; do
      echo "Testing DUT=$dut, PIPE=$pipe"

      # Don't create golden, just run ASIC flow
      ASIC_STR="set asictop $dut; set W 0; set PIPE $pipe; set M 0"
      cd asic
      # Run synthesis and PAR without copying to golden
      dc_shell-xg-t -f asic-synth.tcl -x "$ASIC_STR" > /dev/null 2>&1
      innovus -64 -no_gui -execute "$ASIC_STR" -files asic-par.tcl > /dev/null 2>&1
      cd ..

      RESULT_FILE="asic/asic-post-par-area.${dut}.0.0.${pipe}.rpt"
      GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.0.0.${pipe}.rpt"

      compare_asic_metrics $RESULT_FILE $GOLDEN_FILE "DUT=$dut,PIPE=$pipe"
    done
  done
fi

# ======================================
# Adders ASIC Testing
# ======================================

if [[ $RUN_ADDER -eq 1 ]]; then
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
          echo "Testing DUT=$dut, W=$w, M=$m, PIPE=$pipe"

          ASIC_STR="set asictop $dut; set W $w; set PIPE $pipe; set M $m"
          cd asic
          dc_shell-xg-t -f asic-synth.tcl -x "$ASIC_STR" > /dev/null 2>&1
          innovus -64 -no_gui -execute "$ASIC_STR" -files asic-par.tcl > /dev/null 2>&1
          cd ..

          RESULT_FILE="asic/asic-post-par-area.${dut}.${w}.${m}.${pipe}.rpt"
          GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.${w}.${m}.${pipe}.rpt"

          compare_asic_metrics $RESULT_FILE $GOLDEN_FILE "DUT=$dut,W=$w,M=$m,PIPE=$pipe"
        done
      done
    done
  done
fi

# ====================================
# Partial Products ASIC Testing
# ====================================

if [[ $RUN_PP -eq 1 ]]; then
  for w in 4 8 16 32 64; do
    for pipe in 0 1; do
      for dut in binary_pp booth_pp; do
        echo "Testing DUT=$dut, W=$w, PIPE=$pipe"

        ASIC_STR="set asictop $dut; set W $w; set PIPE $pipe; set M 0"
        cd asic
        dc_shell-xg-t -f asic-synth.tcl -x "$ASIC_STR" > /dev/null 2>&1
        innovus -64 -no_gui -execute "$ASIC_STR" -files asic-par.tcl > /dev/null 2>&1
        cd ..

        RESULT_FILE="asic/asic-post-par-area.${dut}.${w}.0.${pipe}.rpt"
        GOLDEN_FILE="asic/asic-post-par-area.${dut}.golden.${w}.0.${pipe}.rpt"

        compare_asic_metrics $RESULT_FILE $GOLDEN_FILE "DUT=$dut,W=$w,PIPE=$pipe"
      done
    done
  done
fi

# ======================================
# Compressor Trees ASIC Testing
# ======================================

if [[ $RUN_COMPRESSOR -eq 1 ]]; then
  for w in 4 64; do
    for pipe in 0 1; do
      for alg in dadda bickerstaff faonly; do
        for sign in unsigned signed; do
          for dut in binary booth; do
            if [[ $dut == "booth" && $sign == "unsigned" ]]; then
              continue
            fi

            echo "Testing compressor_tree($dut), W=$w, ALG=$alg, SIGN=$sign, PIPE=$pipe"

            unsigned_val=$([[ $sign == "unsigned" ]] && echo 1 || echo 0)
            booth_val=$([[ $dut == "booth" ]] && echo 1 || echo 0)

            # Generate RTL
            if [[ $sign == "unsigned" ]]; then
              python3 compressor_tree.py -w $w --encoding=$dut --unsigned --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
            else
              python3 compressor_tree.py -w $w --encoding=$dut --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
            fi

            ASIC_STR="set asictop compressor_tree; set W $w; set PIPE $pipe; set M 0"
            cd asic
            dc_shell-xg-t -f asic-synth.tcl -x "$ASIC_STR" > /dev/null 2>&1
            innovus -64 -no_gui -execute "$ASIC_STR" -files asic-par.tcl > /dev/null 2>&1
            cd ..

            RESULT_FILE="asic/asic-post-par-area.compressor_tree.${w}.0.${pipe}.rpt"
            GOLDEN_FILE="asic/asic-post-par-area.compressor_tree.${dut}.golden.${w}.${alg}.${sign}.${pipe}.rpt"

            compare_asic_metrics $RESULT_FILE $GOLDEN_FILE "DUT=compressor_tree($dut),W=$w,ALG=$alg,SIGN=$sign,PIPE=$pipe"
          done
        done
      done
    done
  done
fi

# ======================================
# Prefix Tree ASIC Testing
# ======================================

if [[ $RUN_PREFIX -eq 1 ]]; then
  for w in 4 8 16 32 64 128; do
    for pipe in 0 1; do
      for technique in brent-kung sklansky kogge-stone; do
        echo "Testing prefix_tree, W=$w, TECHNIQUE=$technique, PIPE=$pipe"

        # Generate RTL
        python3 prefix_tree.py -w $w --technique=$technique --verilog -o rtl/prefix_tree.sv > /dev/null 2>&1

        ASIC_STR="set asictop prefix_tree; set W $w; set PIPE $pipe; set M 0"
        cd asic
        dc_shell-xg-t -f asic-synth.tcl -x "$ASIC_STR" > /dev/null 2>&1
        innovus -64 -no_gui -execute "$ASIC_STR" -files asic-par.tcl > /dev/null 2>&1
        cd ..

        RESULT_FILE="asic/asic-post-par-area.prefix_tree.${w}.0.${pipe}.rpt"
        GOLDEN_FILE="asic/asic-post-par-area.prefix_tree.golden.${w}.${technique}.${pipe}.rpt"

        compare_asic_metrics $RESULT_FILE $GOLDEN_FILE "DUT=prefix_tree,W=$w,TECHNIQUE=$technique,PIPE=$pipe"
      done
    done
  done
fi

# Print summary
echo ""
echo "===== ASIC Grading Summary ====="
TOTAL_TESTS=$(grep "^GRADE," grade_asic.log | wc -l)
PASSED_TESTS=$(grep "^GRADE,1" grade_asic.log | wc -l)
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $((TOTAL_TESTS - PASSED_TESTS))"
if [[ $TOTAL_TESTS -gt 0 ]]; then
  PASS_RATE=$(python3 -c "print(f'{$PASSED_TESTS / $TOTAL_TESTS * 100:.2f}')")
  echo "Pass Rate: ${PASS_RATE}%"
fi
echo "================================"
