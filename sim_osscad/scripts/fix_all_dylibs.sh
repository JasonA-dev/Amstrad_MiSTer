#!/bin/bash
# Script to fix all dylib files in the OSS CAD Suite installation

OSS_CAD_SUITE_PATH="$HOME/os/oss-cad-suite"

echo "Fixing all dylib files in the OSS CAD Suite installation..."
echo ""

# Function to remove quarantine from a file
fix_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "  Fixing $(basename "$file")"
        # Remove quarantine attribute
        xattr -d com.apple.quarantine "$file" 2>/dev/null || true
        # Make executable if not already
        chmod +x "$file" 2>/dev/null || true
    fi
}

# Find all dylib files and fix them
echo "Searching for all .dylib files..."
dylib_files=$(find "$OSS_CAD_SUITE_PATH" -name "*.dylib" -type f)

if [ -z "$dylib_files" ]; then
    echo "No .dylib files found in $OSS_CAD_SUITE_PATH."
else
    echo "Found $(echo "$dylib_files" | wc -l | tr -d ' ') .dylib files."
    
    # Process each file
    while IFS= read -r file; do
        fix_file "$file"
    done <<< "$dylib_files"
fi

# Find all .vpi files and fix them too
echo ""
echo "Searching for all .vpi files..."
vpi_files=$(find "$OSS_CAD_SUITE_PATH" -name "*.vpi" -type f)

if [ -z "$vpi_files" ]; then
    echo "No .vpi files found in $OSS_CAD_SUITE_PATH."
else
    echo "Found $(echo "$vpi_files" | wc -l | tr -d ' ') .vpi files."
    
    # Process each file
    while IFS= read -r file; do
        fix_file "$file"
    done <<< "$vpi_files"
fi

# Find all .so files and fix them too
echo ""
echo "Searching for all .so files..."
so_files=$(find "$OSS_CAD_SUITE_PATH" -name "*.so" -type f)

if [ -z "$so_files" ]; then
    echo "No .so files found in $OSS_CAD_SUITE_PATH."
else
    echo "Found $(echo "$so_files" | wc -l | tr -d ' ') .so files."
    
    # Process each file
    while IFS= read -r file; do
        fix_file "$file"
    done <<< "$so_files"
fi

# Look specifically for libbz2.1.0.8.dylib
echo ""
bz2_lib=$(find "$OSS_CAD_SUITE_PATH" -name "libbz2.1.0.8.dylib" -type f)
if [ -n "$bz2_lib" ]; then
    echo "Found libbz2.1.0.8.dylib at $bz2_lib"
    fix_file "$bz2_lib"
    
    # Show its permissions
    echo "  Permissions:"
    ls -la "$bz2_lib"
else
    echo "libbz2.1.0.8.dylib not found in the OSS CAD Suite installation."
fi

echo ""
echo "Done fixing library files."
echo ""
echo "If you still get security warnings when running the simulation,"
echo "you may need to manually allow the files in:"
echo "System Preferences > Security & Privacy > General"
echo "after attempting to run your simulation." 