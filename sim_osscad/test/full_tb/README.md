# Amstrad MiSTer Test Environment

This directory contains test files for validating the Amstrad MiSTer core, specifically focused on syntax and compatibility checks.

## Test Files

1. `run_yosys_check.sh` - Runs a syntax check using Yosys on the Amstrad.sv file. This is the most reliable test for syntax validation as Yosys has good SystemVerilog support.

2. `run_verilator_check.sh` - Runs a lint check using Verilator, which is more strict about SystemVerilog syntax.

3. `run_amstrad_wrapper.sh` - Attempts to run a full SystemVerilog simulation with Icarus Verilog (iverilog), but currently fails due to syntax issues in some of the peripheral modules.

## Current Status

The main Amstrad.sv file now passes syntax checking with Yosys after our fixes:

1. Fixed SystemVerilog array literals by replacing `'{sd_lba,sd_lba}` with `{sd_lba, sd_lba}` and `'{sd_buff_din,sd_buff_din}` with `{sd_buff_din, sd_buff_din}` to improve compatibility.

2. Fixed variable declarations inside always blocks by moving `div`, `page`, and `combo` declarations outside their respective always blocks.

However, complete simulation is not yet possible due to:

1. Syntax errors in peripheral modules like YM2149.sv, hid.sv, and GX4000_sprite.sv
2. Incompatibilities between SystemVerilog features used in these modules and the Icarus Verilog simulator

## How to Run Tests

To validate the syntax of the main Amstrad.sv file:

```bash
./run_yosys_check.sh
```

This test should pass, confirming that the main module is syntactically correct for synthesis tools.

## Next Steps

To enable full simulation, the following would be needed:

1. Fix syntax issues in peripheral modules (YM2149.sv, hid.sv, etc.)
2. Complete stub implementation of peripheral modules
3. Create a more comprehensive testbench

For now, the syntax check confirms that the Amstrad.sv file itself is compatible with synthesis tools like Quartus, which is sufficient for MiSTer FPGA implementation.

# Amstrad CPC / GX4000 Testbench

This directory contains testbenches for testing the Amstrad CPC and GX4000 FPGA implementation.

## Available Testbenches


```### 1. Wrapper Testbench (`tb_amstrad_wrapper.sv`)

This is a testbench that wraps around the Amstrad.sv file without modifying it. This approach allows testing the Amstrad core directly and checking for warnings or errors in synthesis.

To run this testbench:
```
./run_amstrad_wrapper.sh
```

To view the waveform:
```
./run_amstrad_wrapper.sh --wave
```

## Testbench Structure

Testbench provides:
- Clock generation for system and audio clocks
- Reset sequence
- HPS interface mock to provide settings and controls
- Video signal monitoring
- Audio signal monitoring
- SD card interface mocks
- UART interface mocks
- SDRAM interface mocks

The wrapper testbench is particularly useful for testing the Amstrad.sv file in isolation, making it easier to identify issues specific to that module without interference from other test infrastructure.

## Common Issues and Debugging

If you encounter compilation errors:
1. Check that all required modules are present in the RTL directories
2. Verify that the include paths are correct in the Makefile
3. Look for syntax errors or incompatibilities with iverilog

For simulation errors:
1. Check the logs in the logs_wrapper directory
2. Use the waveform viewer to examine signal behavior
3. Look for timing violations or initialization problems

## Adding New Tests

When adding new test scenarios:
1. Modify the initial section of the testbench to set up the appropriate inputs
2. Add new monitoring blocks for outputs of interest
3. Update the simulation time if longer runs are needed 