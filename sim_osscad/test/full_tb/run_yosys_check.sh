#!/bin/bash

# Script to run a simple SystemVerilog syntax check on Amstrad.sv using Yosys

# Set the directory paths
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
SIM_DIR="$ROOT_DIR/sim_osscad"
TEST_DIR="$SIM_DIR/test/full_tb"
LOGS_DIR="$TEST_DIR/logs_syntax"

# Target files
TARGET_FILE="$ROOT_DIR/Amstrad.sv"

# OSS CAD Suite setup
export OSS_CAD_SUITE="$HOME/os/oss-cad-suite"
export PATH="$OSS_CAD_SUITE/bin:$PATH"

# Check if OSS CAD Suite is available
if [ ! -d "$OSS_CAD_SUITE" ]; then
  echo "ERROR: OSS CAD Suite not found at $OSS_CAD_SUITE"
  echo "Please install OSS CAD Suite or update the path in this script."
  exit 1
fi

# Check if yosys is available
if ! command -v yosys &> /dev/null; then
  echo "ERROR: Yosys not found in PATH"
  echo "Make sure the OSS CAD Suite bin directory is in your PATH"
  exit 1
fi

# Create log directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Print the environment for debugging
echo "=============================================================="
echo "Running Amstrad SystemVerilog Syntax Check with Yosys"
echo "=============================================================="
echo "ROOT_DIR: $ROOT_DIR"
echo "SIM_DIR: $SIM_DIR"
echo "TEST_DIR: $TEST_DIR"
echo "LOGS_DIR: $LOGS_DIR"
echo "TARGET_FILE: $TARGET_FILE"
echo "OSS_CAD_SUITE: $OSS_CAD_SUITE"
echo "yosys path: $(which yosys)"
echo "=============================================================="

# Create a temporary yosys script
YOSYS_SCRIPT="$LOGS_DIR/check_syntax.ys"
echo "read_verilog -sv $TARGET_FILE" > "$YOSYS_SCRIPT"
echo "proc; opt" >> "$YOSYS_SCRIPT"

# Run yosys to check syntax
echo "Running Yosys syntax check..."
yosys -q -l "$LOGS_DIR/yosys_output.log" "$YOSYS_SCRIPT" 2>&1
YOSYS_RESULT=$?

if [ $YOSYS_RESULT -eq 0 ]; then
  echo "Yosys syntax check PASSED - No syntax errors detected"
  echo "=============================================================="
  echo "SystemVerilog syntax check completed successfully"
  echo "=============================================================="
else
  echo "Yosys syntax check FAILED - See $LOGS_DIR/yosys_output.log for details"
  echo "Error summary:"
  grep -E "ERROR|Error|error" "$LOGS_DIR/yosys_output.log"
  exit 1
fi

exit 0 