# Makefile for Full Amstrad testbench simulation

# Directories
BUILD_DIR = build
LOGS_DIR = logs
RTL_DIR = ../../../rtl
ROOT_DIR = ../../..
GX4000_DIR = $(RTL_DIR)/GX4000
T80_DIR = $(RTL_DIR)/T80
U765_DIR = $(RTL_DIR)/u765
PLL_DIR = $(RTL_DIR)/pll
PLAYCITY_DIR = $(RTL_DIR)/playcity

# Files
TESTBENCH = tb_amstrad_full
TOP_SV = $(ROOT_DIR)/Amstrad.sv
TOP_MODULE = emu

# Commands
IVERILOG = iverilog
VVP = vvp
GTKWAVE = gtkwave

# Include all necessary files
INCLUDE_DIRS = \
	-I$(ROOT_DIR) \
	-I$(RTL_DIR) \
	-I$(GX4000_DIR) \
	-I$(T80_DIR) \
	-I$(U765_DIR) \
	-I$(PLL_DIR) \
	-I$(PLAYCITY_DIR)

# Flags
IVERILOG_FLAGS = -g2012 -Wall -DSTUB_MODULES $(INCLUDE_DIRS)

# Source files
SRC_FILES = \
	$(TESTBENCH).sv \
	$(TOP_SV)

# Main RTL files
RTL_FILES = \
	$(wildcard $(RTL_DIR)/*.v) \
	$(wildcard $(RTL_DIR)/*.sv) \
	$(wildcard $(GX4000_DIR)/*.v) \
	$(wildcard $(GX4000_DIR)/*.sv) \
	$(wildcard $(T80_DIR)/*.v) \
	$(wildcard $(U765_DIR)/*.v) \
	$(wildcard $(PLL_DIR)/*.v) \
	$(wildcard $(PLAYCITY_DIR)/*.v)

# Targets
all: clean prepare compile simulate

prepare:
	@mkdir -p $(BUILD_DIR)
	@mkdir -p $(LOGS_DIR)

compile:
	@echo "Compiling simulation..."
	@echo "Using top-level file: $(TOP_SV)"
	@$(IVERILOG) $(IVERILOG_FLAGS) -o $(BUILD_DIR)/$(TESTBENCH).vvp \
	        -s $(TESTBENCH) $(SRC_FILES) $(RTL_FILES) \
	        || (echo "Compilation failed!"; exit 1)
	@echo "Compilation successful!"

simulate:
	@echo "Running simulation..."
	@$(VVP) $(BUILD_DIR)/$(TESTBENCH).vvp -vcd | tee $(LOGS_DIR)/simulation.log \
	        || (echo "Simulation failed!"; exit 1)
	@echo "Simulation completed successfully!"
	@echo "Results are in $(LOGS_DIR)/simulation.log"

wave:
	@$(GTKWAVE) $(BUILD_DIR)/$(TESTBENCH).vcd &

clean:
	@rm -rf $(BUILD_DIR) $(LOGS_DIR)
	@echo "Clean completed"

.PHONY: all prepare compile simulate wave clean 