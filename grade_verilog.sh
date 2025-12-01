#!/bin/zsh

# RTL Correctness Grading Script
# Tests functional correctness of all modules

DIR=~/ece493t31-f25_arith/labs-admin/lab2-sol

# Set to 1 to skip make data/run and just collect results from existing logs
COLLECT_ONLY=0

if [[ "$(pwd)" != "$DIR" ]]; then
  # Copy reference files
  for file in \
    generate_adder_data.py \
    generate_gpk_data.py \
    generate_binary_pp_data.py \
    generate_booth_pp_data.py \
    generate_prefix_cell_data.py \
    generate_compressor_tree_data.py
  do
    cp $DIR/data/$file ./data
  done

  # Copy testbench files
  for file in \
    test_adder.sv \
    test_binary_pp.sv \
    test_prefix_cell.sv \
    test_gpk.sv \
    test_booth_pp.sv \
    test_compressor_tree.sv
  do
    cp $DIR/tb/$file ./tb
  done

  cp $DIR/Makefile .
  cp $DIR/params2* .
  cp $DIR/*.params .

fi

source env.sh

L="grading_logs"
mkdir -p "$L"

# Helper function to extract result from log file
extract_result() {
  local logfile=$1
  if [[ -f "$logfile" ]]; then
    grade=$(grep "GRADE:" "$logfile" | cut -d':' -f2 | tr -d '[:space:]')
    if [[ "$grade" == "1" ]]; then
      echo "PASS"
    else
      echo "FAIL"
    fi
  else
    echo "FAIL"
  fi
}

# Initialize results tracking
echo "# RTL Test Results" > grade_rtl.log
echo "timestamp=$(date +%s)" >> grade_rtl.log

# Test result arrays
typeset -A test_results

RUN_GPK=1
RUN_ADDER=1
RUN_PP=1
RUN_COMPRESSOR=1
RUN_PREFIX_CELL=1
RUN_PREFIX_TREE=1
RUN_MULTIPLIER=1

# ======================================
# BASIC BLOCKS: 25% RTL correctness
# Tests: rca, csa, cla, booth_pp, prefix_cell
# ======================================

echo "\n=== Testing Basic Blocks (25%) ==="

basic_block_tests=0
basic_block_pass=0

# GPK
if [[ $RUN_GPK -eq 1 ]]; then
for pipe in 0 1; do
  dut=gpk
  logfile="$L/${dut}_pipe${pipe}.log"
  echo "PIPE=$pipe" > ${dut}.params
  if [[ $COLLECT_ONLY -eq 0 ]]; then
    rm -rf data/*.hex 2>/dev/null || true
    make data DUT=${dut} PARAMS_FILE="${dut}.params" >/dev/null 2>&1 || true
    make run  DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
  fi
  result=$(extract_result "$logfile")
  basic_block_tests=$((basic_block_tests + 1))
  if [[ "$result" == "PASS" ]]; then
    basic_block_pass=$((basic_block_pass + 1))
  fi
done
fi

# Test Adders: RCA, CSA, CLA
if [[ $RUN_ADDER -eq 1 ]]; then
for dut in rca csa cla; do
  echo "  Testing $dut..."
  for w in 32; do
    if [[ $dut == rca ]]; then
      m_vals=(0)
    else
      m_vals=($(seq 2 2 $((w/2))))
    fi
    for m in $m_vals; do
      for pipe in 0 1; do
        logfile="$L/${dut}_w${w}_m${m}_pipe${pipe}.log"
        echo "W=$w" > ${dut}.params
        echo "M=$m" >> ${dut}.params
        echo "PIPE=$pipe" >> ${dut}.params
        if [[ $COLLECT_ONLY -eq 0 ]]; then
          rm -rf data/*.hex 2>/dev/null || true
          make data DUT=adder PARAMS_FILE="${dut}.params" >/dev/null 2>&1 || true
          make run  DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
        fi
        result=$(extract_result "$logfile")
        basic_block_tests=$((basic_block_tests + 1))
        if [[ "$result" == "PASS" ]]; then
          basic_block_pass=$((basic_block_pass + 1))
        fi
      done
    done
  done
done
fi

# Test Partial Products
if [[ $RUN_PP -eq 1 ]]; then
for w in 128; do
  for dut in binary_pp booth_pp; do
    echo "  Testing $dut (W=$w)..."
    for pipe in 0 1; do
      logfile="$L/${dut}_w${w}_pipe${pipe}.log"
      echo "W=$w" > ${dut}.params
      echo "PIPE=$pipe" >> ${dut}.params
      if [[ $COLLECT_ONLY -eq 0 ]]; then
        rm -rf data/*.hex 2>/dev/null || true
        make data DUT=${dut} PARAMS_FILE="${dut}.params" >/dev/null 2>&1 || true
        make run  DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
      fi
      result=$(extract_result "$logfile")
      basic_block_tests=$((basic_block_tests + 1))
      if [[ "$result" == "PASS" ]]; then
        basic_block_pass=$((basic_block_pass + 1))
      fi
    done
  done
done
fi

# Test Prefix Cell
if [[ $RUN_PREFIX_CELL -eq 1 ]]; then
dut=prefix_cell
echo "  Testing $dut..."
for pipe in 0 1; do
  logfile="$L/${dut}_pipe${pipe}.log"
  echo "PIPE=$pipe" > ${dut}.params
  if [[ $COLLECT_ONLY -eq 0 ]]; then
    rm -rf data/*.hex 2>/dev/null || true
    make data DUT=${dut} PARAMS_FILE="${dut}.params" >/dev/null 2>&1 || true
    make run  DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
  fi
  result=$(extract_result "$logfile")
  basic_block_tests=$((basic_block_tests + 1))
  if [[ "$result" == "PASS" ]]; then
    basic_block_pass=$((basic_block_pass + 1))
  fi
done
fi

# Calculate basic block score
if [[ $basic_block_tests -gt 0 ]]; then
  basic_block_score=$(awk "BEGIN {printf \"%.2f\", 25.0 * $basic_block_pass / $basic_block_tests}")
else
  basic_block_score=0.00
fi

echo "basic_blocks_rtl=$basic_block_pass/$basic_block_tests" >> grade_rtl.log
echo "  Result: $basic_block_pass/$basic_block_tests tests passed (Score: $basic_block_score/25.0)"

# ======================================
# COMPRESSOR TREES: 25% total
# - 10% smart signed binary
# - 10% smart signed booth
# - 2.5% naive signed binary
# - 2.5% naive signed booth
# ======================================

echo "\n=== Testing Compressor Trees (25%) ==="

typeset -A compressor_configs
compressor_configs=(
  "smart_signed_binary" "signed binary 0"
  "smart_signed_booth" "signed booth 0"
  "naive_signed_binary" "signed binary 1"
  "naive_signed_booth" "signed booth 1"
)

typeset -A compressor_scores
typeset -A compressor_tests

if [[ $RUN_COMPRESSOR -eq 1 ]]; then
for config_name sign_enc_naive in ${(kv)compressor_configs}; do
  read sign encoding naivesignext <<< "$sign_enc_naive"

  echo "  Testing $config_name ($sign $encoding, naive=$naivesignext)..."

  tests=0
  pass=0

  for w in 128; do
    for pipe in 0 1; do
      for alg in dadda bickerstaff faonly; do
        [[ $encoding == "booth" ]] && booth=1 || booth=0
        [[ $sign == "unsigned" ]] && unsigned=1 || unsigned=0

        dut=compressor_tree
        logfile="$L/${dut}_${config_name}_w${w}_pipe${pipe}_${alg}.log"
        echo "W=$w" > ${dut}.params
        echo "PIPE=$pipe" >> ${dut}.params
        echo "BOOTH=$booth" >> ${dut}.params
        echo "UNSIGNED=$unsigned" >> ${dut}.params

        if [[ $COLLECT_ONLY -eq 0 ]]; then
          rm -f data/*.hex 2>/dev/null || true
          if [[ $sign == "unsigned" ]]; then
            python3 data/generate_compressor_tree_data.py -w $w --encoding=$encoding --unsigned -n 128 -o data -r tb/top.h > /dev/null 2>&1
            python3 compressor_tree.py -w $w --encoding=$encoding --unsigned --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
          else
            python3 data/generate_compressor_tree_data.py -w $w --encoding=$encoding -n 128 -o data -r tb/top.h > /dev/null 2>&1
            if [[ $naivesignext -eq 1 ]]; then
              python3 compressor_tree.py -w $w --encoding=$encoding --algorithm=$alg --naive-sign-ext -o rtl/compressor_tree.sv > /dev/null 2>&1
            else
              python3 compressor_tree.py -w $w --encoding=$encoding --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
            fi
          fi
          make run DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
        fi

        result=$(extract_result "$logfile")
        tests=$((tests + 1))
        if [[ "$result" == "PASS" ]]; then
          pass=$((pass + 1))
        fi
      done
    done
  done

  compressor_tests[$config_name]=$tests
  compressor_scores[$config_name]=$pass
  echo "compressor_${config_name}_rtl=$pass/$tests" >> grade_rtl.log
  echo "    Result: $pass/$tests tests passed"
done
fi

# ======================================
# PREFIX TREES: 5% total
# ======================================

echo "\n=== Testing Prefix Trees (5%) ==="

prefix_tests=0
prefix_pass=0

if [[ $RUN_PREFIX_TREE -eq 1 ]]; then
for w in 128; do
  for pipe in 0 1; do
    for technique in brent-kung sklansky kogge-stone; do
      echo "  Testing prefix_tree (W=$w, $technique)..."
      dut=prefix_tree
      logfile="$L/${dut}_w${w}_pipe${pipe}_${technique}.log"
      echo "W=$w" > ${dut}.params
      echo "PIPE=$pipe" >> ${dut}.params
      if [[ $COLLECT_ONLY -eq 0 ]]; then
        rm -rf data/*.hex 2>/dev/null || true
        make data DUT=${dut} PARAMS_FILE="${dut}.params" >/dev/null 2>&1 || true
        python3 prefix_tree.py -w ${w} --technique=$technique --verilog -o rtl/prefix_tree.sv > /dev/null 2>&1
        make run  DUT=${dut} PARAMS_FILE="${dut}.params" >"$logfile" 2>&1 || true
      fi
      result=$(extract_result "$logfile")
      prefix_tests=$((prefix_tests + 1))
      if [[ "$result" == "PASS" ]]; then
        prefix_pass=$((prefix_pass + 1))
      fi
    done
  done
done
fi

echo "prefix_tree_rtl=$prefix_pass/$prefix_tests" >> grade_rtl.log
echo "  Result: $prefix_pass/$prefix_tests tests passed"

# ======================================
# MULTIPLIER: 2.5% total
# ======================================

echo "\n=== Testing Multiplier (2.5%) ==="

multiplier_tests=0
multiplier_pass=0

chmod +x multiplier.sh
m=2

if [[ $RUN_MULTIPLIER -eq 1 ]]; then
for w in 64; do
  for encoding in binary booth; do
    for comp_alg in dadda bickerstaff; do
      for prefix_alg in kogge-stone brent-kung sklansky; do
        for pipe in 0 1 6; do
          for unsigned in 0 1; do
            # Skip booth unsigned combinations
            if [[ $encoding == "booth" && $unsigned == 1 ]]; then
              continue
            fi

            echo "  Testing multiplier (W=$w, $encoding, $comp_alg, $prefix_alg, pipe=$pipe, unsigned=$unsigned)..."

            [[ $encoding == "booth" ]] && booth=1 || booth=0
            dut=multiplier
            logfile="$L/${dut}_w${w}_${encoding}_${comp_alg}_${prefix_alg}_pipe${pipe}_u${unsigned}.log"
            echo "W=$w" > ${dut}.params
            echo "M=$m" >> ${dut}.params
            echo "BOOTH=$booth" >> ${dut}.params
            echo "PIPE=$pipe" >> ${dut}.params

            if [[ $COLLECT_ONLY -eq 0 ]]; then
              rm -rf data/*.hex 2>/dev/null || true
              if [[ $unsigned -eq 1 ]]; then
                python3 data/generate_multiplier_data.py -w $w -n 128 -o data -r tb/top.h --unsigned > /dev/null 2>&1
              else
                python3 data/generate_multiplier_data.py -w $w -n 128 -o data -r tb/top.h > /dev/null 2>&1
              fi
              zsh ./multiplier.sh W=$w ENCODING=$encoding COMPRESSOR_ALGORITHM=$comp_alg PREFIX_ALGORITHM=$prefix_alg FINAL_ADDER=xor M=$m PIPE=$pipe UNSIGNED=$unsigned TESTS=128 > /dev/null 2>&1
              make run DUT=${dut} PARAMS_FILE=${dut}.params >"$logfile" 2>&1 || true
            fi

            result=$(extract_result "$logfile")
            multiplier_tests=$((multiplier_tests + 1))
            if [[ "$result" == "PASS" ]]; then
              multiplier_pass=$((multiplier_pass + 1))
            fi
          done
        done
      done
    done
  done
done

echo "multiplier_rtl=$multiplier_pass/$multiplier_tests" >> grade_rtl.log
echo "  Result: $multiplier_pass/$multiplier_tests tests passed"
fi

# ======================================
# RTL SUMMARY
# ======================================

echo ""
echo "=== RTL Test Summary ==="
echo "  Basic Blocks: $basic_block_pass/$basic_block_tests tests (25% weight)"
echo "  Compressor smart_signed_binary: ${compressor_scores[smart_signed_binary]}/${compressor_tests[smart_signed_binary]} tests (10% weight)"
echo "  Compressor smart_signed_booth: ${compressor_scores[smart_signed_booth]}/${compressor_tests[smart_signed_booth]} tests (10% weight)"
echo "  Compressor naive_signed_binary: ${compressor_scores[naive_signed_binary]}/${compressor_tests[naive_signed_binary]} tests (2.5% weight)"
echo "  Compressor naive_signed_booth: ${compressor_scores[naive_signed_booth]}/${compressor_tests[naive_signed_booth]} tests (2.5% weight)"
echo "  Prefix Trees: $prefix_pass/$prefix_tests tests (5% weight)"
echo "  Multiplier: $multiplier_pass/$multiplier_tests tests (2.5% weight)"

# Calculate RTL scores
basic_rtl_score=$(echo "$basic_block_pass $basic_block_tests" | awk '{if($2>0) printf "%.2f", 25.0*$1/$2; else print 0}')
comp_smart_binary_rtl=$(echo "${compressor_scores[smart_signed_binary]} ${compressor_tests[smart_signed_binary]}" | awk '{if($2>0) printf "%.2f", 10.0*$1/$2; else print 0}')
comp_smart_booth_rtl=$(echo "${compressor_scores[smart_signed_booth]} ${compressor_tests[smart_signed_booth]}" | awk '{if($2>0) printf "%.2f", 10.0*$1/$2; else print 0}')
comp_naive_binary_rtl=$(echo "${compressor_scores[naive_signed_binary]} ${compressor_tests[naive_signed_binary]}" | awk '{if($2>0) printf "%.2f", 2.5*$1/$2; else print 0}')
comp_naive_booth_rtl=$(echo "${compressor_scores[naive_signed_booth]} ${compressor_tests[naive_signed_booth]}" | awk '{if($2>0) printf "%.2f", 2.5*$1/$2; else print 0}')
prefix_rtl_score=$(echo "$prefix_pass $prefix_tests" | awk '{if($2>0) printf "%.2f", 5.0*$1/$2; else print 0}')
mult_rtl_score=$(echo "$multiplier_pass $multiplier_tests" | awk '{if($2>0) printf "%.2f", 2.5*$1/$2; else print 0}')

total_rtl=$(echo "$basic_rtl_score $comp_smart_binary_rtl $comp_smart_booth_rtl $comp_naive_binary_rtl $comp_naive_booth_rtl $prefix_rtl_score $mult_rtl_score" | awk '{printf "%.2f", $1+$2+$3+$4+$5+$6+$7}')

echo ""
echo "=== RTL Grade ==="
echo "  Basic Blocks RTL: $basic_rtl_score / 25.0"
echo "  Compressor smart_signed_binary RTL: $comp_smart_binary_rtl / 10.0"
echo "  Compressor smart_signed_booth RTL: $comp_smart_booth_rtl / 10.0"
echo "  Compressor naive_signed_binary RTL: $comp_naive_binary_rtl / 2.5"
echo "  Compressor naive_signed_booth RTL: $comp_naive_booth_rtl / 2.5"
echo "  Prefix Trees RTL: $prefix_rtl_score / 5.0"
echo "  Multiplier RTL: $mult_rtl_score / 2.5"
echo "  ---"
echo "  Total RTL: $total_rtl / 57.5"
echo ""
echo "RTL testing complete. Results saved to grade_rtl.log"
