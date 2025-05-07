#!/bin/bash
# Script to specifically fix the system.vpi file

SYSTEM_VPI="$HOME/os/oss-cad-suite/lib/ivl/system.vpi"

if [ -f "$SYSTEM_VPI" ]; then
    echo "Fixing $SYSTEM_VPI..."
    
    # Remove quarantine attribute
    xattr -d com.apple.quarantine "$SYSTEM_VPI" 2>/dev/null || true
    
    # Ensure it's executable
    chmod +x "$SYSTEM_VPI"
    
    echo "Permissions on $SYSTEM_VPI:"
    ls -la "$SYSTEM_VPI"
    
    echo ""
    echo "If you still get security warnings, you can manually allow the file in"
    echo "System Preferences > Security & Privacy > General after attempting to run your simulation."
else
    echo "Error: $SYSTEM_VPI file not found."
    exit 1
fi

# Attempt to fix all files in the ivl directory
IVL_DIR="$HOME/os/oss-cad-suite/lib/ivl"
echo "Fixing all files in $IVL_DIR..."

if [ -d "$IVL_DIR" ]; then
    for file in "$IVL_DIR"/*; do
        if [ -f "$file" ]; then
            echo "  Removing quarantine from $(basename "$file")"
            xattr -d com.apple.quarantine "$file" 2>/dev/null || true
            chmod +x "$file"
        fi
    done
else
    echo "IVL directory not found: $IVL_DIR"
fi

echo "Done." 