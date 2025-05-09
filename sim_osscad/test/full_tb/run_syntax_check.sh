#!/bin/bash

# Script to run a simple SystemVerilog syntax check on Amstrad.sv

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

# Create log directory if it doesn't exist
mkdir -p "$LOGS_DIR"

# Print the environment for debugging
echo "=============================================================="
echo "Running Amstrad SystemVerilog Syntax Check"
echo "=============================================================="
echo "ROOT_DIR: $ROOT_DIR"
echo "SIM_DIR: $SIM_DIR"
echo "TEST_DIR: $TEST_DIR"
echo "LOGS_DIR: $LOGS_DIR"
echo "TARGET_FILE: $TARGET_FILE"
echo "OSS_CAD_SUITE: $OSS_CAD_SUITE"
echo "=============================================================="

# Perform syntax check using sv2v
echo "Running SystemVerilog check using sv2v..."
sv2v "$TARGET_FILE" > /dev/null 2> "$LOGS_DIR/sv2v_errors.log"
SV2V_RESULT=$?

if [ $SV2V_RESULT -eq 0 ]; then
  echo "sv2v syntax check passed - No SystemVerilog parsing errors detected"
else
  echo "sv2v syntax check FAILED - See $LOGS_DIR/sv2v_errors.log for details"
  cat "$LOGS_DIR/sv2v_errors.log"
  exit 1
fi

# Perform additional syntax check using yosys (if available)
if command -v yosys &> /dev/null; then
  echo "Running Yosys check..."
  echo "read_verilog -sv $TARGET_FILE" | yosys -q > "$LOGS_DIR/yosys_output.log" 2>&1
  YOSYS_RESULT=$?
  
  if [ $YOSYS_RESULT -eq 0 ]; then
    echo "Yosys syntax check passed"
  else
    echo "Yosys syntax check FAILED - See $LOGS_DIR/yosys_output.log for details"
    cat "$LOGS_DIR/yosys_output.log"
    exit 1
  fi
else
  echo "Yosys not found, skipping additional syntax check"
fi

echo "=============================================================="
echo "SystemVerilog syntax check completed successfully"
echo "=============================================================="

exit 0 