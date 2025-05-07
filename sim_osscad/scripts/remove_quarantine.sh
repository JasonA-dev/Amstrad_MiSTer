#!/bin/bash
# Script to remove quarantine attributes from OSS CAD Suite executables

OSS_CAD_SUITE_PATH="$HOME/os/oss-cad-suite"

echo "Removing quarantine attributes from OSS CAD Suite executables..."
echo ""

# Function to remove quarantine from a directory
remove_quarantine() {
    local dir="$1"
    echo "Processing directory: $dir"
    
    if [ -d "$dir" ]; then
        # Process regular files in the directory
        for file in "$dir"/*; do
            if [ -f "$file" ] && [ -x "$file" ]; then
                echo "  Removing quarantine from $(basename "$file")"
                xattr -d com.apple.quarantine "$file" 2>/dev/null || true
            fi
        done
        
        # Process all subdirectories recursively
        for subdir in "$dir"/*; do
            if [ -d "$subdir" ]; then
                remove_quarantine "$subdir"
            fi
        done
    else
        echo "Directory $dir does not exist."
    fi
}

# Function to remove quarantine from specific files
remove_quarantine_file() {
    local file="$1"
    if [ -f "$file" ]; then
        echo "  Removing quarantine from $(basename "$file")"
        xattr -d com.apple.quarantine "$file" 2>/dev/null || true
    else
        echo "File $file does not exist."
    fi
}

# Run the function on the bin and libexec directories
remove_quarantine "$OSS_CAD_SUITE_PATH/bin"
remove_quarantine "$OSS_CAD_SUITE_PATH/libexec"

# Also process the lib directory for VPI modules and dynamically loaded libraries
echo "Processing VPI modules and libraries..."
if [ -d "$OSS_CAD_SUITE_PATH/lib" ]; then
    # Handle all .vpi files
    find "$OSS_CAD_SUITE_PATH/lib" -name "*.vpi" -type f -print | while read -r file; do
        remove_quarantine_file "$file"
    done
    
    # Handle all .dylib files
    find "$OSS_CAD_SUITE_PATH/lib" -name "*.dylib" -type f -print | while read -r file; do
        remove_quarantine_file "$file"
    done
    
    # Handle all .so files
    find "$OSS_CAD_SUITE_PATH/lib" -name "*.so" -type f -print | while read -r file; do
        remove_quarantine_file "$file"
    done
else
    echo "Library directory $OSS_CAD_SUITE_PATH/lib does not exist."
fi

echo ""
echo "Done removing quarantine attributes."
echo "You might still need to manually allow executables in System Preferences > Security & Privacy"
echo "when you first run them." 