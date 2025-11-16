##
## Name  Supply  Process  Temp
##--------------------------------------------
## BC    1.1V    FF       0C
## TC    1.0V    TT       25C
## WC    0.9V    SS       0C
##

create_rc_corner -name rc_corner \
  -cap_table "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Back_End/lef/tcbn65gplus_200a/techfiles/capable/cln65g+_1p09m+alrdl_typical_top2.capable"

create_library_set -name wcl_typical \
  -timing [list "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplustc.lib"]

create_library_set -name wcl_slow \
  -timing [list "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gpluswc.lib"]

create_library_set -name wcl_fast \
  -timing [list "/CMC/kits/tsmc_65nm_libs/tcbn65gplus_200a/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65gplus_140b/tcbn65gplusbc.lib"]

create_delay_corner -name delay_corner_wcl_typical \
                    -early_library_set wcl_typical \
                    -late_library_set wcl_typical \
                    -rc_corner rc_corner

create_delay_corner -name delay_corner_wcl_slow \
                    -early_library_set wcl_slow \
                    -late_library_set wcl_slow \
                    -rc_corner rc_corner

create_delay_corner -name delay_corner_wcl_fast \
                    -early_library_set wcl_fast \
                    -late_library_set wcl_fast \
                    -rc_corner rc_corner

create_constraint_mode -name functional_wcl_slow    -sdc_files [list constraints.sdc]
create_constraint_mode -name functional_wcl_fast    -sdc_files [list constraints.sdc]
create_constraint_mode -name functional_wcl_typical -sdc_files [list constraints.sdc]

create_analysis_view -name view_functional_wcl_slow    -constraint_mode functional_wcl_slow    -delay_corner delay_corner_wcl_slow
create_analysis_view -name view_functional_wcl_fast    -constraint_mode functional_wcl_fast    -delay_corner delay_corner_wcl_fast
create_analysis_view -name view_functional_wcl_typical -constraint_mode functional_wcl_typical -delay_corner delay_corner_wcl_typical

set_analysis_view -setup [list view_functional_wcl_slow view_functional_wcl_fast view_functional_wcl_typical] \
                  -hold [list view_functional_wcl_slow view_functional_wcl_fast view_functional_wcl_typical]
