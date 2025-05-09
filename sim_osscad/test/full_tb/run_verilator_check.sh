#!/bin/bash

# Script to run the Amstrad Verilator lint-only check

# Set the directory paths
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
SIM_DIR="$ROOT_DIR/sim_osscad"
TEST_DIR="$SIM_DIR/test/full_tb"
BUILD_DIR="$TEST_DIR/build_verilator"
LOGS_DIR="$TEST_DIR/logs_verilator"

# OSS CAD Suite setup
export OSS_CAD_SUITE="$HOME/os/oss-cad-suite"
export PATH="$OSS_CAD_SUITE/bin:$PATH"

# Check if OSS CAD Suite is available
if [ ! -d "$OSS_CAD_SUITE" ]; then
  echo "ERROR: OSS CAD Suite not found at $OSS_CAD_SUITE"
  echo "Please install OSS CAD Suite or update the path in this script."
  exit 1
fi

# Check if Verilator is available
if ! command -v verilator &> /dev/null; then
  echo "ERROR: Verilator not found in PATH"
  echo "Make sure the OSS CAD Suite bin directory is in your PATH"
  exit 1
fi

# Create directories if they don't exist
mkdir -p "$BUILD_DIR"
mkdir -p "$LOGS_DIR"

# Print the environment for debugging
echo "=============================================================="
echo "Running Amstrad Verilator Lint Check"
echo "=============================================================="
echo "ROOT_DIR: $ROOT_DIR"
echo "SIM_DIR: $SIM_DIR"
echo "TEST_DIR: $TEST_DIR"
echo "BUILD_DIR: $BUILD_DIR"
echo "LOGS_DIR: $LOGS_DIR"
echo "OSS_CAD_SUITE: $OSS_CAD_SUITE"
echo "verilator path: $(which verilator)"
echo "=============================================================="

# Change to the test directory
cd "$TEST_DIR" || { echo "Failed to change to test directory"; exit 1; }

# Clean any previous builds
echo "Cleaning previous build..."
make -f Makefile_verilator clean

# Target files
TOP_SV_REL="$(ROOT_DIR)/Amstrad.sv"
TOP_SV="$ROOT_DIR/Amstrad.sv"
TOP_MODULE="Amstrad"

# Commands
VERILATOR="$BIN_DIR/verilator"
TRACE_PLAYER="$BIN_DIR/gtkwave"

# Create a temporary yosys script
VERILATOR_SCRIPT="$LOGS_DIR/verilator_check.cmd"
echo "cd $TEST_DIR" > "$VERILATOR_SCRIPT"
echo "exec $VERILATOR $VFLAGS $TOP_SV" >> "$VERILATOR_SCRIPT"

# Run yosys to check syntax
echo "Running Verilator lint check..."
bash "$VERILATOR_SCRIPT" > "$LOGS_DIR/verilator.log" 2>&1
VERILATOR_RESULT=$?

if [ $VERILATOR_RESULT -eq 0 ]; then
  echo "Verilator lint check PASSED - No syntax errors detected"
  echo "=============================================================="
  echo "Verilator lint check completed successfully"
  echo "Results are in $LOGS_DIR/verilator.log"
  echo "=============================================================="
else
  echo "Verilator lint check FAILED - See $LOGS_DIR/verilator.log for details"
  echo "Error summary:"
  grep -E "ERROR|Error|error" "$LOGS_DIR/verilator.log"
  exit 1;
fi

exit 0 