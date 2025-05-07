#!/bin/bash

# Set the path to our local bin directory with fixed wrappers
LOCAL_BIN_DIR="$(pwd)/local_bin"
export PATH="$LOCAL_BIN_DIR:$PATH"

# Set the path to OSS CAD Suite
OSS_CAD_SUITE_PATH="$HOME/os/oss-cad-suite"
export PATH="$OSS_CAD_SUITE_PATH/bin:$PATH"

# Make sure other environment variables are set correctly
export LD_LIBRARY_PATH="$OSS_CAD_SUITE_PATH/lib:$LD_LIBRARY_PATH"
export DYLD_LIBRARY_PATH="$OSS_CAD_SUITE_PATH/lib:$DYLD_LIBRARY_PATH"

# Add debugging
echo "Current PATH: $PATH"
echo "Current working directory: $(pwd)"
echo "OSS CAD Suite path: $OSS_CAD_SUITE_PATH"

# Check if build directory exists, if not create it
if [ ! -d "build" ]; then
    mkdir -p build
fi

# Create log directory if not exists
if [ ! -d "logs" ]; then
    mkdir -p logs
fi

# Try with our custom wrapper first
echo "Running GX4000 ASIC simulation with Icarus Verilog..."
echo "Using custom wrapper at: $LOCAL_BIN_DIR/iverilog"

# First try with just the basic command
if [ -x "$LOCAL_BIN_DIR/iverilog" ]; then
    echo "Testing custom iverilog wrapper command..."
    "$LOCAL_BIN_DIR/iverilog" -V
    
    if [ $? -ne 0 ]; then
        echo "Custom iverilog wrapper command failed!"
        exit 1
    else
        echo "Custom iverilog wrapper command worked! Proceeding with compilation..."
        
        # Try compilation with our parameters
        "$LOCAL_BIN_DIR/iverilog" -g2012 -DSIMULATION -o build/tb_gx4000_asic.vvp ../rtl/GX4000/GX4000_ASIC.sv tb_gx4000_asic.sv
        
        if [ $? -ne 0 ]; then
            echo "Compilation failed!"
            exit 1
        fi
    fi
else
    echo "ERROR: Custom iverilog wrapper script not found or not executable!"
    exit 1
fi

# Run the simulation
echo "Running simulation..."
if [ -x "$LOCAL_BIN_DIR/vvp" ]; then
    echo "Using custom VVP wrapper at: $LOCAL_BIN_DIR/vvp"
    "$LOCAL_BIN_DIR/vvp" build/tb_gx4000_asic.vvp | tee logs/simulation.log
    if [ $? -ne 0 ]; then
        echo "Simulation failed!"
        exit 1
    fi
else
    echo "ERROR: Custom VVP wrapper not found or not executable!"
    exit 1
fi

echo "Simulation completed successfully!"
echo "Results are in logs/simulation.log"

# Launch GTKWave if available and requested
if [ "$1" == "wave" ]; then
    echo "Opening waveform viewer..."
    if [ -x "$LOCAL_BIN_DIR/gtkwave" ]; then
        echo "Using custom GTKWave wrapper at: $LOCAL_BIN_DIR/gtkwave"
        "$LOCAL_BIN_DIR/gtkwave" build/tb_gx4000_asic.vcd &
    else
        echo "GTKWave wrapper not found - cannot display waveform"
    fi
fi

exit 0 