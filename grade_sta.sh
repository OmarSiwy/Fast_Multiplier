#!/bin/zsh

echo "" > grade_sta.log

RUN_GPK=1
RUN_ADDER=1
RUN_PP=1
RUN_COMPRESSOR=1
RUN_PREFIX=1

# Function to perform STA and check timing
perform_sta() {
  local dut=$1
  local base_name=$2
  local log_prefix=$3

  local synth_netlist="asic/asic-post-synth.${base_name}.v"
  local par_netlist="asic/asic-post-par.${base_name}.v"
  local synth_sdc="asic/constraints.sdc"
  local spef_file="asic/post-par.${base_name}.spef"

  # Check if netlists exist
  if [[ ! -f $synth_netlist ]]; then
    echo "${log_prefix},STATUS=MISSING_SYNTH_NETLIST" >> grade_sta.log
    echo "GRADE,0" >> grade_sta.log
    return 1
  fi

  if [[ ! -f $par_netlist ]]; then
    echo "${log_prefix},STATUS=MISSING_PAR_NETLIST" >> grade_sta.log
    echo "GRADE,0" >> grade_sta.log
    return 1
  fi

  # Create STA script for post-synthesis
  STA_SYNTH_SCRIPT="asic/sta-synth.${base_name}.tcl"
  cat > $STA_SYNTH_SCRIPT << 'EOFSYNTH'
set_app_var target_library "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db"
set_app_var link_library "* /CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db"
set_app_var power_enable_analysis true
EOFSYNTH

  cat >> $STA_SYNTH_SCRIPT << EOFSYNTH2
read_verilog "$synth_netlist"
current_design $dut
link_design
create_clock clk -name ideal_clock1 -period 1
report_timing -nosplit > asic/sta-synth-timing.${base_name}.rpt
report_constraint -all_violators > asic/sta-synth-violations.${base_name}.rpt
exit
EOFSYNTH2

  # Create STA script for post-PAR
  STA_PAR_SCRIPT="asic/sta-par.${base_name}.tcl"
  cat > $STA_PAR_SCRIPT << 'EOFPAR'
set_app_var target_library "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db"
set_app_var link_library "* /CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db"
set_app_var power_enable_analysis true
EOFPAR

  cat >> $STA_PAR_SCRIPT << EOFPAR2
read_verilog "$par_netlist"
current_design $dut
link_design
create_clock clk -name ideal_clock1 -period 1
EOFPAR2

  # Add SPEF if it exists
  if [[ -f $spef_file ]]; then
    echo "read_parasitics -format spef \"$spef_file\"" >> $STA_PAR_SCRIPT
  fi

  cat >> $STA_PAR_SCRIPT << 'EOFPAR3'
report_timing -nosplit > asic/sta-par-timing.${base_name}.rpt
report_constraint -all_violators > asic/sta-par-violations.${base_name}.rpt
exit
EOFPAR3

  # Run post-synthesis STA
  cd asic
  pt_shell -f $(basename $STA_SYNTH_SCRIPT) > /dev/null 2>&1
  pt_shell -f $(basename $STA_PAR_SCRIPT) > /dev/null 2>&1
  cd ..

  # Check timing reports
  SYNTH_TIMING_RPT="asic/sta-synth-timing.${base_name}.rpt"
  PAR_TIMING_RPT="asic/sta-par-timing.${base_name}.rpt"
  SYNTH_VIOL_RPT="asic/sta-synth-violations.${base_name}.rpt"
  PAR_VIOL_RPT="asic/sta-par-violations.${base_name}.rpt"

  if [[ ! -f $SYNTH_TIMING_RPT || ! -f $PAR_TIMING_RPT ]]; then
    echo "${log_prefix},STATUS=STA_FAILED" >> grade_sta.log
    echo "GRADE,0" >> grade_sta.log
    return 1
  fi

  # Extract slack values
  SYNTH_SLACK=$(grep -i "slack" $SYNTH_TIMING_RPT | grep -i "MET\|VIOLATED" | head -1 | awk '{print $(NF-1)}' | tr -d '()')
  PAR_SLACK=$(grep -i "slack" $PAR_TIMING_RPT | grep -i "MET\|VIOLATED" | head -1 | awk '{print $(NF-1)}' | tr -d '()')

  # Count violations
  SYNTH_VIOLATIONS=$(grep -c "VIOLATED" $SYNTH_VIOL_RPT 2>/dev/null || echo "0")
  PAR_VIOLATIONS=$(grep -c "VIOLATED" $PAR_VIOL_RPT 2>/dev/null || echo "0")

  # Check timing pass
  SYNTH_PASS=0
  PAR_PASS=0

  if [[ $SYNTH_VIOLATIONS -eq 0 && -n $SYNTH_SLACK ]]; then
    SYNTH_SLACK_POSITIVE=$(python3 -c "print(1 if float('$SYNTH_SLACK') >= 0 else 0)" 2>/dev/null || echo "0")
    SYNTH_PASS=$SYNTH_SLACK_POSITIVE
  fi

  if [[ $PAR_VIOLATIONS -eq 0 && -n $PAR_SLACK ]]; then
    PAR_SLACK_POSITIVE=$(python3 -c "print(1 if float('$PAR_SLACK') >= 0 else 0)" 2>/dev/null || echo "0")
    PAR_PASS=$PAR_SLACK_POSITIVE
  fi

  # Overall pass
  if [[ $SYNTH_PASS -eq 1 && $PAR_PASS -eq 1 ]]; then
    PASS=1
    STATUS="PASS"
  else
    PASS=0
    STATUS="FAIL"
  fi

  # Log results
  echo "${log_prefix},STATUS=$STATUS,SYNTH_SLACK=${SYNTH_SLACK},PAR_SLACK=${PAR_SLACK},SYNTH_VIOLS=${SYNTH_VIOLATIONS},PAR_VIOLS=${PAR_VIOLATIONS}" >> grade_sta.log
  echo "  Post-Synthesis: Slack=$SYNTH_SLACK, Violations=$SYNTH_VIOLATIONS" >> grade_sta.log
  echo "  Post-PAR:       Slack=$PAR_SLACK, Violations=$PAR_VIOLATIONS" >> grade_sta.log
  echo "GRADE,$PASS" >> grade_sta.log

  return 0
}

# ======================================
# GPK STA Testing
# ======================================

if [[ $RUN_GPK -eq 1 ]]; then
  for pipe in 0 1; do
    for dut in gpk; do
      echo "Testing STA for DUT=$dut, PIPE=$pipe"
      perform_sta $dut "${dut}.0.0.${pipe}" "DUT=$dut,PIPE=$pipe"
    done
  done
fi

# ======================================
# Adders STA Testing
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
          echo "Testing STA for DUT=$dut, W=$w, M=$m, PIPE=$pipe"
          perform_sta $dut "${dut}.${w}.${m}.${pipe}" "DUT=$dut,W=$w,M=$m,PIPE=$pipe"
        done
      done
    done
  done
fi

# ====================================
# Partial Products STA Testing
# ====================================

if [[ $RUN_PP -eq 1 ]]; then
  for w in 4 8 16 32 64; do
    for pipe in 0 1; do
      for dut in binary_pp booth_pp; do
        echo "Testing STA for DUT=$dut, W=$w, PIPE=$pipe"
        perform_sta $dut "${dut}.${w}.0.${pipe}" "DUT=$dut,W=$w,PIPE=$pipe"
      done
    done
  done
fi

# ======================================
# Compressor Trees STA Testing
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

            echo "Testing STA for compressor_tree($dut), W=$w, ALG=$alg, SIGN=$sign, PIPE=$pipe"
            perform_sta "compressor_tree" "compressor_tree.${w}.0.${pipe}" "DUT=compressor_tree($dut),W=$w,ALG=$alg,SIGN=$sign,PIPE=$pipe"
          done
        done
      done
    done
  done
fi

# ======================================
# Prefix Tree STA Testing
# ======================================

if [[ $RUN_PREFIX -eq 1 ]]; then
  for w in 4 8 16 32 64 128; do
    for pipe in 0 1; do
      for technique in brent-kung sklansky kogge-stone; do
        echo "Testing STA for prefix_tree, W=$w, TECHNIQUE=$technique, PIPE=$pipe"
        perform_sta "prefix_tree" "prefix_tree.${w}.0.${pipe}" "DUT=prefix_tree,W=$w,TECHNIQUE=$technique,PIPE=$pipe"
      done
    done
  done
fi

# Print summary
echo ""
echo "===== STA Grading Summary ====="
TOTAL_TESTS=$(grep "^GRADE," grade_sta.log | wc -l)
PASSED_TESTS=$(grep "^GRADE,1" grade_sta.log | wc -l)
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $((TOTAL_TESTS - PASSED_TESTS))"
if [[ $TOTAL_TESTS -gt 0 ]]; then
  PASS_RATE=$(python3 -c "print(f'{$PASSED_TESTS / $TOTAL_TESTS * 100:.2f}')")
  echo "Pass Rate: ${PASS_RATE}%"
fi
echo "================================"
