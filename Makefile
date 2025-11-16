# Default DUT if not specified
DUT ?= rca
PIPE ?= 0

TEST_FILE = tb/test.cpp
LOG_SUFFIX = $(DUT)
SRC =  rtl/$(DUT).sv rtl/fa.sv rtl/ha.sv
ifneq ($(DUT),rca)
  SRC += rtl/rca.sv
endif

# Define which DUTs use the generic adder testbench
ADDER_DUTS := rca csa cla

# Conditionally select the testbench file
ifeq ($(DUT),$(filter $(DUT),$(ADDER_DUTS)))
  # For adders, use generic testbench and pass TOPNAME
  TEST_SV = tb/test_adder.sv
  VFLAGS += -DTOPNAME=$(DUT) -DPIPE=$(PIPE)
else
  # For other DUTs, use DUT-specific testbench
  TEST_SV = tb/test_$(DUT).sv
endif

SIM_DIR = /tmp/$(USER)/sim/
VCD ?= 0
VCD_FILE_STR ?= "test.vcd"
TOP = top
PARALLEL_SEQ ?= :100

VFLAGS += -DTESTDIR=\"$(PWD)/data/\" -DTOP=$(TOP)
_CFLAGS = -CFLAGS

ifeq ($(VCD), 1)
VFLAGS+= --trace
_CFLAGS+= -DVCD -CFLAGS -DVCD_FILE=\\\"$(VCD_FILE_STR)\\\"
endif

# Add parameter override for PIPE
VFLAGS += -DPIPE=$(PIPE)

ASIC_STR = "set asictop $(DUT); set W $(W); set PIPE $(PIPE); set M $(M)"

compile: $(SRC) $(TEST_FILE)
	mkdir -p $(SIM_DIR)
	verilator $(VFLAGS) \
		$(_CFLAGS) \
		-Itb\
		-Irtl\
		--clk clk\
		--cc $(SRC)\
		$(TEST_SV) \
		--exe $(PWD)/$(TEST_FILE) \
		-top-module $(TOP) \
		--Mdir $(SIM_DIR)
	make -C $(SIM_DIR) -f V$(TOP).mk V$(TOP)

run: compile
	echo "Verilator Running Test for $(DUT)"
	cd $(SIM_DIR) && ./V$(TOP) > log.csv
	cat $(SIM_DIR)/log.csv

asic-run:
	make asic DUT=rca W=16 PIPE=0
	make asic DUT=rca W=16 PIPE=1

asic:
	cd asic; dc_shell-xg-t -f asic-synth.tcl -x $(ASIC_STR); innovus -64 -no_gui -execute $(ASIC_STR) -files asic-par.tcl; cd ..
	cp asic/asic-post-par-area.$(DUT).$(W).$(M).$(PIPE).rpt asic/asic-post-par-area.$(DUT).golden.$(W).$(M).$(PIPE).rpt


.PHONY: clean asic

clean:
	rm -rf sim
	rm -f log.csv times.csv
