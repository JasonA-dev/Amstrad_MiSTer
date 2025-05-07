# GX4000 ASIC Simulation with OSS CAD Suite

This directory contains files for simulating the GX4000 ASIC using the open-source OSS CAD Suite tools.

## Requirements

You need to have OSS CAD Suite installed and available in your PATH. OSS CAD Suite includes:
- Yosys
- Icarus Verilog
- Verilator
- GTKWave

Installation instructions can be found at: https://github.com/YosysHQ/oss-cad-suite-build

## Directory Structure

- `tb_gx4000_asic.sv` - The testbench file for the GX4000 ASIC
- `Makefile` - Makefile for building and running the simulation
- `run_sim.sh` - Shell script to quickly run the simulation
- `build/` - Build directory (created automatically)
- `logs/` - Log directory for simulation output (created automatically)

## Running the Simulation

### Using the Script

The easiest way to run the simulation is using the provided shell script:

```bash
./run_sim.sh
```

To run the simulation and open the waveform viewer:

```bash
./run_sim.sh wave
```

### Using Make

Alternatively, you can use the Makefile:

```bash
make sim_icarus    # Run with Icarus Verilog
make sim_verilator # Run with Verilator
make wave          # Open the waveform viewer
make clean         # Clean the build directory
```

## Tests Included

The testbench contains several tests for the GX4000 ASIC:

1. **Unlock Sequence Test** - Tests the 17-byte ASIC unlock sequence
2. **Force Unlock Test** - Tests the force_unlock feature
3. **ASIC State Test** - Tests setting the ASIC state and checking protection status

## Customizing the Tests

To add or modify tests, edit the `tb_gx4000_asic.sv` file. The testbench is structured using tasks for each test, making it easy to add new tests.

## Analyzing Results

Simulation results are displayed in the console and saved to `logs/simulation.log`. 
Waveforms are saved in VCD format to `build/tb_gx4000_asic.vcd` and can be viewed with GTKWave.

## Troubleshooting

If you encounter issues:

1. Make sure OSS CAD Suite is properly installed and in your PATH
2. Check the log files for detailed error messages
3. Verify that the GX4000_ASIC.sv file is compatible with the testbench 