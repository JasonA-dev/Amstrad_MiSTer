#!/bin/bash

# Script to run the Amstrad wrapper testbench

# Set the directory paths
SCRIPT_DIR=$(dirname "$0")
ROOT_DIR=$(cd "$SCRIPT_DIR/../../.." && pwd)
SIM_DIR="$ROOT_DIR/sim_osscad"
TEST_DIR="$SIM_DIR/test/full_tb"
BUILD_DIR="$TEST_DIR/build_wrapper"
LOGS_DIR="$TEST_DIR/logs_wrapper"

# OSS CAD Suite setup
export OSS_CAD_SUITE="$HOME/os/oss-cad-suite"
export PATH="$OSS_CAD_SUITE/bin:$PATH"

# Check if OSS CAD Suite is available
if [ ! -d "$OSS_CAD_SUITE" ]; then
  echo "ERROR: OSS CAD Suite not found at $OSS_CAD_SUITE"
  echo "Please install OSS CAD Suite or update the path in this script."
  exit 1
fi

# Create directories if they don't exist
mkdir -p "$BUILD_DIR"
mkdir -p "$LOGS_DIR"

# Print the environment for debugging
echo "=============================================================="
echo "Running Amstrad Wrapper Testbench"
echo "=============================================================="
echo "ROOT_DIR: $ROOT_DIR"
echo "SIM_DIR: $SIM_DIR"
echo "TEST_DIR: $TEST_DIR"
echo "BUILD_DIR: $BUILD_DIR"
echo "LOGS_DIR: $LOGS_DIR"
echo "OSS_CAD_SUITE: $OSS_CAD_SUITE"
echo "iverilog path: $(which iverilog)"
echo "=============================================================="

# Change to the test directory
cd "$TEST_DIR" || { echo "Failed to change to test directory"; exit 1; }

# Clean any previous builds
if [ -d "$BUILD_DIR" ]; then
    echo "Cleaning previous build..."
    rm -rf "$BUILD_DIR"/*
fi

# Run the Makefile
echo "Running make for the wrapper testbench..."
make -f Makefile_wrapper clean prepare compile || { echo "Compilation failed"; exit 1; }

# Run the simulation
echo "Running simulation..."
make -f Makefile_wrapper simulate || { echo "Simulation failed"; exit 1; }

# Open waveform if requested
if [ "$1" == "--wave" ]; then
    echo "Opening waveform viewer..."
    make -f Makefile_wrapper wave
fi

echo "=============================================================="
echo "Simulation completed successfully"
echo "Results are in $LOGS_DIR/simulation.log"
echo "=============================================================="

exit 0 