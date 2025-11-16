set_app_var target_library "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplusbc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswcl.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplustc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluslt.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswcz.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplusml.db"

set_app_var link_library "* /CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplusbc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswcl.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplustc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluslt.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswcz.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.db \
/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplusml.db"


saif_map -start

analyze -format sverilog ../rtl/ha.sv
analyze -format sverilog ../rtl/fa.sv
analyze -format sverilog ../rtl/gpk.sv
analyze -format sverilog ../rtl/rca.sv
analyze -format sverilog ../rtl/csa.sv
analyze -format sverilog ../rtl/cla.sv
analyze -format sverilog ../rtl/booth_pp.sv
analyze -format sverilog ../rtl/binary_pp.sv
analyze -format sverilog ../rtl/compressor_tree.sv
analyze -format sverilog ../rtl/prefix_cell.sv
analyze -format sverilog ../rtl/prefix_tree.sv
analyze -format sverilog ../rtl/multiplier.sv

elaborate $asictop -param "W=>$W,M=>$M,PIPE=>$PIPE"
current_design ${asictop}_W${W}_M${M}_PIPE${PIPE}

check_design

create_clock clk -name ideal_clock1 -period 1

compile

saif_map -create_map -input "$asictop.$W.$M.$PIPE.saif" -source_instance "TOP/$asictop"

saif_map -type ptpx -write_map "asic-post-synth.$asictop.$W.$M.$PIPE.namemap"

write -format verilog -hierarchy -output asic-post-synth.$asictop.$W.$M.$PIPE.v
write -format ddc     -hierarchy -output asic-post-synth.$asictop.$W.$M.$PIPE.ddc

report_timing -nosplit -transition_time -nets -attributes > asic-post-synth-timing.$asictop.$W.$M.$PIPE.rpt
report_area -nosplit -hierarchy                           >   asic-post-synth-area.$asictop.$W.$M.$PIPE.rpt
report_power -nosplit -hierarchy                          >  asic-post-synth-power.$asictop.$W.$M.$PIPE.rpt

exit
