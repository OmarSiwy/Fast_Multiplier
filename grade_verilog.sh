#!/bin/zsh

echo "" > grade.log

RUN_GPK=0
RUN_ADDER=0
RUN_PP=0
RUN_COMPRESSOR=1
RUN_PREFIX=0

RUN_MULTIPLIER=0

# ======================================
# GPK
# ======================================

rm -rf data/*.hex
if [[ $RUN_GPK -eq 1 ]]; then
for pipe in 0 1; do
  for dut in gpk; do
    python3 data/generate_${dut}_data.py --exhaustive -o data -r tb
    make run DUT=${dut} PIPE=$pipe
    grade=$(grep "GRADE:" /tmp/`whoami`/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
    echo "DUT=$dut,PIPE=$pipe,PASS=$grade" >> grade.log
    #[[ $grade -eq 1 ]] && grade=10 || grade=0
    echo "GRADE,$grade" >> grade.log
  done
done
fi

# ======================================
# Adders
# ======================================

if [[ $RUN_ADDER -eq 1 ]]; then
for dut in rca csa cla; do
  # iterate every width from 4 through 128 (inclusive)
  for w in 4 128; do
    if [[ $dut == rca ]]; then
      m_vals=(0)
    else
      # multiples of 2 up to floor(w/2)
      # keep the same "m" choices as before (even multiples) — adjust if you need odd m values
      m_vals=($(seq 2 2 $((w/2))))
    fi
    for m in $m_vals; do
      for pipe in 0 1; do
        python3 data/generate_adder_data.py -w $w -m $m -n 1024 -o data -r tb
        make run DUT=$dut PIPE=$pipe
        grade=$(grep "GRADE:" /tmp/`whoami`/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
        echo "DUT=$dut,W=$w,M=$m,PIPE=$pipe,PASS=$grade" >> grade.log
        echo "GRADE,$grade" >> grade.log
      done
    done
  done
done
fi

# ====================================
# Partial Products
# ====================================

if [[ $RUN_PP -eq 1 ]]; then
for w in 4 128; do
  for pipe in 0 1; do
    for dut in binary_pp booth_pp; do
      python3 data/generate_${dut}_data.py -w $w -n 128 -o data -r tb
      make run DUT=${dut} PIPE=$pipe
      grade=$(grep "GRADE:" /tmp/`whoami`/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
      echo "DUT=$dut,W=$w,PIPE=$pipe,PASS=$grade" >> grade.log
      #[[ $grade -eq 1 ]] && grade=10 || grade=0
      echo "GRADE,$grade" >> grade.log
    done
  done
done
fi

# ======================================
# Compressor Trees
# ====================================

if [[ $RUN_COMPRESSOR -eq 1 ]]; then
  for w in 4 64; do
    for pipe in 0 1; do
      for alg in dadda bickerstaff faonly; do
        for sign in unsigned signed; do
          for dut in binary booth; do
            # Skip booth unsigned combinations
            if [[ $dut == "booth" && $sign == "unsigned" ]]; then
              continue
            fi

            # Clean old test data to prevent contamination
            rm -f data/test_*.hex

            # Generate files based on sign
            if [[ $sign == "unsigned" ]]; then
              python3 compressor_tree.py -w $w --encoding=$dut --unsigned --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
              python3 data/generate_compressor_tree_data.py -w $w --encoding=$dut --unsigned -n 128 -o data -r tb/top.h > /dev/null 2>&1
            else
              python3 compressor_tree.py -w $w --encoding=$dut --algorithm=$alg -o rtl/compressor_tree.sv > /dev/null 2>&1
              python3 data/generate_compressor_tree_data.py -w $w --encoding=$dut -n 128 -o data -r tb/top.h > /dev/null 2>&1
            fi

            unsigned_val=$([[ $sign == "unsigned" ]] && echo 1 || echo 0)
            booth_val=$([[ $dut == "booth" ]] && echo 1 || echo 0)

            # Compile and run immediately
            make run DUT=compressor_tree PIPE=$pipe W=$w UNSIGNED=$unsigned_val ALG=$alg BOOTH=$booth_val
            grade=$(grep "GRADE:" /tmp/$(whoami)/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
            echo "DUT=$dut,W=$w,ALG=$alg,SIGN=$sign,PIPE=$pipe,PASS=$grade" >> grade.log
            echo "GRADE,$grade" >> grade.log
          done
        done
      done
    done
  done
fi

# ======================================
# Prefix Cell
# ======================================

if [[ $RUN_PREFIX -eq 1 ]]; then
  for w in 4 8 16 32 64 128; do
    for pipe in 0 1; do
      for technique in brent-kung sklansky kogge-stone; do
        # Generate prefix tree RTL
        python3 prefix_tree.py -w $w --technique=$technique --graphviz --verilog -o rtl/prefix_tree.sv > /dev/null 2>&1

        # Generate test data for prefix tree
        python3 data/generate_prefix_cell_data.py -w $w -n 128 -o data -r tb/top.h > /dev/null 2>&1

        # Run simulation
        make run DUT=prefix_tree PIPE=$pipe W=$w TECHNIQUE=$technique

        grade=$(grep "GRADE:" /tmp/$(whoami)/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
        echo "DUT=prefix_tree,W=$w,TECHNIQUE=$technique,PIPE=$pipe,PASS=$grade" >> grade.log
        echo "GRADE,$grade" >> grade.log
      done
    done
  done
fi

# ======================================
# Multiplier
# ======================================

if [[ $RUN_MULTIPLIER -eq 1 ]]; then
    for w in 4 8 16 32 64; do
        for encoding in binary booth; do
            for comp_alg in dadda bickerstaff faonly; do
                for prefix_alg in kogge-stone brent-kung sklansky; do
                    for m in 0 2 4; do
                        for pipe in 0 1; do
                        for sign in unsigned signed; do
                            # Skip booth unsigned combinations
                            if [[ $encoding == "booth" && $sign == "unsigned" ]]; then
                                continue
                            fi

                            # Build Multiplier
                            chmod +x multiplier.sh
                            # Usage: ./multiplier.sh W=<width> ENCODING=<binary|booth> COMPRESSOR_ALGORITHM=<dadda|bickerstaff|faonly> \
                            #        PREFIX_ALGORITHM=<kogge-stone|brent-kung|sklansky> FINAL_ADDER=<xor> M=<pipeline_stages> PIPE=<pipelining_level> -DSIGNED=<0|1>
                            ./multiplier.sh W=$w ENCODING=$encoding COMPRESSOR_ALGORITHM=$comp_alg PREFIX_ALGORITHM=$prefix_alg FINAL_ADDER=xor M=$m PIPE=$pipe > /dev/null 2>&1

                            # Generate test data for multiplier
                            python3 data/generate_multiplier_data.py -w $w -n 128 -o data -r tb/top.h > /dev/null 2>&1

                            # Run simulation
                            make run DUT=multiplier PIPE=$pipe W=$w ENCODING=$encoding M=$m

                            grade=$(grep "GRADE:" /tmp/$(whoami)/sim/log.csv | cut -d':' -f2 | tr -d '[:space:]')
                            echo "DUT=$dut,W=$w,PIPE=$pipe,PASS=$grade" >> grade.log
                            echo "GRADE,$grade" >> grade.log
                            done
                        done
                    done
                done
            done
        done
    done
fi
