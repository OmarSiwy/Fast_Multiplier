# =============================================================================
# Lab2 Multiplier Project Makefile
# Supports: simulation, RTL generation, and Yosys area/delay comparison
# =============================================================================

# Default configuration
DUT ?= multiplier
W ?= 16
PIPE ?= 0
M ?= 0
ENCODING ?= booth
COMPRESSOR_ALGORITHM ?= dadda
PREFIX_ALGORITHM ?= kogge-stone
UNSIGNED ?= 0
TESTS ?= 100

# Directories
RTL_DIR = rtl
TB_DIR = tb
DATA_DIR = data
SCRIPTS_DIR = scripts
SIM_DIR = /tmp/$(USER)/sim_$(DUT)
YOSYS_DIR = /tmp/$(USER)/yosys_$(DUT)

# Verilator settings
TOP = top
VCD ?= 0

# Source files based on DUT
ifeq ($(DUT),multiplier)
  SRC = $(RTL_DIR)/multiplier.sv $(RTL_DIR)/compressor_tree.sv \
        $(RTL_DIR)/prefix_tree.sv $(RTL_DIR)/booth_pp.sv \
        $(RTL_DIR)/binary_pp.sv $(RTL_DIR)/prefix_cell.sv \
        $(RTL_DIR)/fa.sv $(RTL_DIR)/ha.sv $(RTL_DIR)/rca.sv
  TEST_SV = $(TB_DIR)/test_multiplier.sv
else ifeq ($(DUT),compressor_tree)
  SRC = $(RTL_DIR)/compressor_tree.sv $(RTL_DIR)/fa.sv $(RTL_DIR)/ha.sv
  TEST_SV = $(TB_DIR)/test_compressor_tree.sv
else ifeq ($(DUT),prefix_tree)
  SRC = $(RTL_DIR)/prefix_tree.sv $(RTL_DIR)/prefix_cell.sv
  TEST_SV = $(TB_DIR)/test_prefix_tree.sv
else ifeq ($(filter $(DUT),rca csa cla),$(DUT))
  SRC = $(RTL_DIR)/$(DUT).sv $(RTL_DIR)/fa.sv $(RTL_DIR)/ha.sv $(RTL_DIR)/gpk.sv
  ifneq ($(DUT),rca)
    SRC += $(RTL_DIR)/rca.sv
  endif
  TEST_SV = $(TB_DIR)/test_adder.sv
else
  SRC = $(RTL_DIR)/$(DUT).sv $(RTL_DIR)/fa.sv $(RTL_DIR)/ha.sv
  TEST_SV = $(TB_DIR)/test_$(DUT).sv
endif

# Verilator flags
VFLAGS = -DTESTDIR=\"$(PWD)/$(DATA_DIR)/\" -DTOP=$(TOP) -DTOPNAME=$(DUT)
VFLAGS += -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL
VFLAGS += -GW=$(W) -GPIPE=$(PIPE) -GM=$(M)
VFLAGS += -DENCODING=\"$(ENCODING)\"

ifeq ($(VCD),1)
  VFLAGS += --trace
endif

# =============================================================================
# RTL Generation Targets
# =============================================================================

.PHONY: gen_compressor_tree gen_prefix_tree gen_multiplier gen_all

gen_compressor_tree:
	@echo "Generating compressor tree: W=$(W), ENCODING=$(ENCODING), ALG=$(COMPRESSOR_ALGORITHM)"
	python3 $(SCRIPTS_DIR)/gen_compressor_tree.py \
		-w $(W) -e $(ENCODING) -a $(COMPRESSOR_ALGORITHM) \
		-o $(RTL_DIR)/compressor_tree.sv \
		$(if $(filter 1,$(UNSIGNED)),--unsigned,)

gen_prefix_tree:
	@echo "Generating prefix tree: W=$(shell echo $$(($(W)*2))), TECHNIQUE=$(PREFIX_ALGORITHM)"
	python3 $(SCRIPTS_DIR)/gen_prefix_tree.py \
		-w $(shell echo $$(($(W)*2))) \
		--technique $(PREFIX_ALGORITHM) \
		-o $(RTL_DIR)/prefix_tree.sv

gen_multiplier: gen_compressor_tree gen_prefix_tree
	@echo "Generating multiplier: W=$(W), ENCODING=$(ENCODING)"
	python3 $(SCRIPTS_DIR)/gen_multiplier.py \
		-w $(W) -e $(ENCODING) \
		-c $(COMPRESSOR_ALGORITHM) -p $(PREFIX_ALGORITHM) \
		--pipe $(PIPE) -m $(M) \
		$(if $(filter 1,$(UNSIGNED)),--unsigned,) \
		-o $(RTL_DIR)

gen_all: gen_multiplier

# =============================================================================
# Data Generation Targets
# =============================================================================

.PHONY: data

data:
	@echo "Generating test data for $(DUT)"
	@mkdir -p $(DATA_DIR)
ifeq ($(DUT),multiplier)
	python3 $(DATA_DIR)/generate_multiplier_data.py \
		-w $(W) -n $(TESTS) \
		$(if $(filter 1,$(UNSIGNED)),-u,) \
		-o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),compressor_tree)
	python3 $(DATA_DIR)/generate_compressor_tree_data.py \
		-w $(W) -n $(TESTS) -e $(ENCODING) \
		$(if $(filter 1,$(UNSIGNED)),--unsigned,) \
		-o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),prefix_tree)
	python3 $(DATA_DIR)/generate_prefix_tree_data.py \
		-w $(shell echo $$(($(W)*2))) -n $(TESTS) \
		-o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(filter $(DUT),rca csa cla),$(DUT))
	python3 $(DATA_DIR)/generate_adder_data.py \
		-w $(W) -n $(TESTS) \
		-o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),gpk)
	python3 $(DATA_DIR)/generate_gpk_data.py \
		-n $(TESTS) -o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),booth_pp)
	python3 $(DATA_DIR)/generate_booth_pp_data.py \
		-w $(W) -n $(TESTS) -o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),binary_pp)
	python3 $(DATA_DIR)/generate_binary_pp_data.py \
		-w $(W) -n $(TESTS) -o $(DATA_DIR)/ -r $(TB_DIR)/
else ifeq ($(DUT),prefix_cell)
	python3 $(DATA_DIR)/generate_prefix_cell_data.py \
		-n $(TESTS) -o $(DATA_DIR)/ -r $(TB_DIR)/
endif

# =============================================================================
# Simulation Targets
# =============================================================================

.PHONY: compile run sim

compile: $(SRC) $(TEST_SV)
	@rm -rf $(SIM_DIR)
	@mkdir -p $(SIM_DIR)
	verilator $(VFLAGS) \
		-I$(TB_DIR) -I$(RTL_DIR) \
		--cc $(SRC) $(TEST_SV) \
		--exe $(PWD)/$(TB_DIR)/test.cpp \
		-top-module $(TOP) \
		--Mdir $(SIM_DIR)
	make -C $(SIM_DIR) -f V$(TOP).mk V$(TOP)

run: compile
	@echo "Running simulation for $(DUT)"
	cd $(SIM_DIR) && ./V$(TOP) > log.csv
	@cat $(SIM_DIR)/log.csv

sim: data compile run

# =============================================================================
# Yosys Analysis Targets
# =============================================================================

.PHONY: yosys_area yosys_compare

# Liberty file (use Yosys example or provide your own)
LIBERTY_FILE ?= /usr/share/yosys/examples/cmos/cmos_cells.lib

yosys_synth:
	@mkdir -p $(YOSYS_DIR)
	@echo "Running Yosys synthesis for $(DUT)..."
	yosys -p " \
		read_verilog -sv $(SRC); \
		hierarchy -top $(DUT); \
		proc; fsm; opt; memory; opt; \
		techmap; opt; \
		stat -json" 2>&1 | tee $(YOSYS_DIR)/synth.log
	@echo "Synthesis complete. Log: $(YOSYS_DIR)/synth.log"

yosys_area:
	@mkdir -p $(YOSYS_DIR)
	@echo "Calculating area for $(DUT)..."
	@yosys -q -p " \
		read_verilog -sv $(SRC); \
		hierarchy -top $(DUT); \
		proc; fsm; opt; memory; opt; \
		techmap; opt; \
		stat" 2>&1 | grep -E "(Number of cells|Estimated|Area)" || true

# =============================================================================
# Multiplier Comparison Target
# =============================================================================

.PHONY: compare_multipliers

compare_multipliers:
	@./compare_multiplier.sh

# =============================================================================
# Clean Targets
# =============================================================================

.PHONY: clean clean_sim clean_data clean_yosys clean_all

clean_sim:
	rm -rf $(SIM_DIR)

clean_data:
	rm -f $(DATA_DIR)/*.hex
	rm -f $(TB_DIR)/top.h

clean_yosys:
	rm -rf $(YOSYS_DIR)

clean: clean_sim clean_data

clean_all: clean clean_yosys
	rm -rf /tmp/$(USER)/sim_*
	rm -rf /tmp/$(USER)/yosys_*

# =============================================================================
# Help
# =============================================================================

.PHONY: help

help:
	@echo "Lab2 Multiplier Project Makefile"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  DUT                  - Design under test (default: multiplier)"
	@echo "  W                    - Bit width (default: 16)"
	@echo "  PIPE                 - Pipeline level (default: 0)"
	@echo "  M                    - Pipeline mode (default: 0)"
	@echo "  ENCODING             - booth or binary (default: booth)"
	@echo "  COMPRESSOR_ALGORITHM - dadda, bickerstaff, faonly (default: dadda)"
	@echo "  PREFIX_ALGORITHM     - brent-kung, sklansky, kogge-stone (default: kogge-stone)"
	@echo "  TESTS                - Number of test vectors (default: 100)"
	@echo ""
	@echo "RTL Generation:"
	@echo "  make gen_compressor_tree  - Generate compressor tree RTL"
	@echo "  make gen_prefix_tree      - Generate prefix tree RTL"
	@echo "  make gen_multiplier       - Generate complete multiplier RTL"
	@echo ""
	@echo "Simulation:"
	@echo "  make data                 - Generate test data"
	@echo "  make compile              - Compile with Verilator"
	@echo "  make run                  - Run simulation"
	@echo "  make sim                  - Full simulation flow (data + compile + run)"
	@echo ""
	@echo "Yosys Analysis:"
	@echo "  make yosys_synth          - Run Yosys synthesis"
	@echo "  make yosys_area           - Show area statistics"
	@echo "  make compare_multipliers  - Compare multiplier configurations"
	@echo ""
	@echo "Examples:"
	@echo "  make gen_multiplier W=32 ENCODING=binary COMPRESSOR_ALGORITHM=dadda"
	@echo "  make sim DUT=multiplier W=16 TESTS=50"
	@echo "  make compare_multipliers"
