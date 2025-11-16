set init_mmmc_file "setup-timing.tcl"
set init_verilog   "asic-post-synth.$asictop.$W.$M.$PIPE.v"
set init_top_cell  "${asictop}_W${W}_M${M}_PIPE${PIPE}"
set init_lef_file  "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/lef/tcbn65gplus_200a/lef/tcbn65gplus_9lmT2.lef"
set init_gnd_net   "VSS"
set init_pwr_net   "VDD"

init_design

floorPlan -r 1.0 0.70 4.0 4.0 4.0 4.0

globalNetConnect VDD -type pgpin -pin VDD -inst * -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -verbose

sroute -nets {VDD VSS}

addRing -nets {VDD VSS} -width 0.6 -spacing 0.5 -layer [list top 7 bottom 7 left 6 right 6]

addStripe -nets {VSS VDD} -layer 6 -direction vertical -width 0.4 -spacing 0.5 -set_to_set_distance 5 -start 0.5

addStripe -nets {VSS VDD} -layer 7 -direction horizontal -width 0.4 -spacing 0.5 -set_to_set_distance 5 -start 0.5

place_design

# ccopt_design

routeDesign

setFillerMode -corePrefix FILL -core "FILL1 FILL2 FILL4"
addFiller

verifyConnectivity

verify_drc

saveNetlist asic-post-par.$asictop.$W.$M.$PIPE.v

extractRC
#rcOut -rc_corner typical -spef asic-post-par.spef
write_sdf post-par.sdf -interconn all -setuphold split

streamOut post-par.$asictop.$W.$M.$PIPE.gds -merge "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/gds/tcbn65gplus_140a/tcbn65gplus.gds"
#-mapFile "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/milkyway/tcbn65gplus_200a/gdsout_6X2Z.map"

report_timing               > asic-post-par-timing.$asictop.$W.$M.$PIPE.rpt
report_area                 >   asic-post-par-area.$asictop.$W.$M.$PIPE.rpt
report_power -hierarchy all >  asic-post-par-power.$asictop.$W.$M.$PIPE.rpt

exit
