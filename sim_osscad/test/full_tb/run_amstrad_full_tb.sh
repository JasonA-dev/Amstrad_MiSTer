#!/bin/bash
# Script to run the full Amstrad testbench

# Define colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Set script paths (corrected)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SIM_DIR="$(cd "$(dirname "$(dirname "$SCRIPT_DIR")")" &> /dev/null && pwd)"
ROOT_DIR="$(cd "$(dirname "$SIM_DIR")" &> /dev/null && pwd)"

echo -e "${BLUE}===== Full Amstrad Testbench Runner =====${NC}"
echo "Current directory: $(pwd)"
echo "Script directory: $SCRIPT_DIR"
echo "Simulation directory: $SIM_DIR"
echo "Root directory: $ROOT_DIR"

# Ensure we're in the correct directory
cd "$SCRIPT_DIR" || { echo -e "${RED}Failed to change to script directory!${NC}"; exit 1; }
echo "Changed to directory: $(pwd)"

# Verify Amstrad.sv exists
if [ ! -f "$ROOT_DIR/Amstrad.sv" ]; then
    echo -e "${RED}Error: Amstrad.sv not found at $ROOT_DIR/Amstrad.sv${NC}"
    echo "Please make sure you're running this script from the correct location."
    exit 1
else
    echo -e "${GREEN}Found Amstrad.sv at $ROOT_DIR/Amstrad.sv${NC}"
fi

# Check if OSS CAD Suite is in PATH
if ! command -v iverilog &> /dev/null; then
    echo -e "${YELLOW}iverilog not found in PATH. Adding OSS CAD Suite...${NC}"
    if [ -d "$HOME/os/oss-cad-suite" ]; then
        export PATH="$HOME/os/oss-cad-suite/bin:$PATH"
        echo "Added OSS CAD Suite to PATH"
    else
        echo -e "${RED}Error: OSS CAD Suite not found at $HOME/os/oss-cad-suite${NC}"
        echo "Please install OSS CAD Suite or adjust the path in this script."
        exit 1
    fi
fi

# Check for wave viewer option
if [ "$1" == "wave" ]; then
    TARGET="compile simulate wave"
    echo -e "${BLUE}Running simulation with waveform viewer${NC}"
else
    TARGET="compile simulate"
    echo -e "${BLUE}Running simulation without waveform viewer${NC}"
    echo "Use './run_amstrad_full_tb.sh wave' to enable waveform viewer"
fi

# Ensure quarantine attributes are removed from binaries
if [ "$(uname)" == "Darwin" ]; then
    echo "Running on macOS, checking quarantine attributes..."
    
    # Use parent directory's script if available
    if [ -f "$SIM_DIR/fix_all_dylibs.sh" ]; then
        echo "Running fix_all_dylibs.sh from parent directory..."
        bash "$SIM_DIR/fix_all_dylibs.sh"
    else
        echo "Removing quarantine attributes from OSS CAD Suite executables..."
        find "$HOME/os/oss-cad-suite" -type f -name "iverilog" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true
        find "$HOME/os/oss-cad-suite" -type f -name "vvp" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true
        find "$HOME/os/oss-cad-suite" -type f -name "gtkwave" -exec xattr -d com.apple.quarantine {} \; 2>/dev/null || true
    fi
fi

# Run the simulation using make
echo -e "${BLUE}Running make $TARGET...${NC}"
make $TARGET

# Check exit status
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Testbench completed successfully!${NC}"
else
    echo -e "${RED}Testbench failed with errors.${NC}"
    exit 1
fi 