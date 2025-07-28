#!/bin/bash

echo "========================================="
echo " Building countdown (i18n enabled)"
echo "========================================="

# Check if GCC is available
if ! command -v gcc &> /dev/null; then
    echo "Error: GCC not found. Please install GCC."
    echo "On Ubuntu/Debian: sudo apt-get install gcc"
    echo "On macOS: xcode-select --install"
    exit 1
fi

echo "Building countdown with internationalization support..."

# Compile with i18n support (Linux/macOS version)
# Note: This will need to be modified to work on Linux/macOS since it uses Windows-specific APIs
# For demonstration, we'll create a cross-compiler version or a native version

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    echo "Note: This program uses Windows-specific APIs."
    echo "For Linux, consider using Wine or creating a Linux-specific version."
    echo "Attempting cross-compilation for Windows..."
    
    if command -v x86_64-w64-mingw32-gcc &> /dev/null; then
        x86_64-w64-mingw32-gcc -o countdown.exe countdown.c
        if [ $? -eq 0 ]; then
            echo "Cross-compilation successful! Use with Wine:"
            echo "wine countdown.exe 3"
        else
            echo "Cross-compilation failed!"
            exit 1
        fi
    else
        echo "Cross-compiler not found. Install with:"
        echo "sudo apt-get install gcc-mingw-w64"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "Note: This program uses Windows-specific APIs."
    echo "For macOS, consider using Wine or creating a macOS-specific version."
    echo "Attempting cross-compilation for Windows..."
    
    if command -v x86_64-w64-mingw32-gcc &> /dev/null; then
        x86_64-w64-mingw32-gcc -o countdown.exe countdown.c
        if [ $? -eq 0 ]; then
            echo "Cross-compilation successful! Use with Wine:"
            echo "wine countdown.exe 3"
        else
            echo "Cross-compilation failed!"
            exit 1
        fi
    else
        echo "Cross-compiler not found. Install with:"
        echo "brew install mingw-w64"
        exit 1
    fi
else
    echo "Unsupported operating system: $OSTYPE"
    exit 1
fi

echo ""
echo "Available language options:"
echo "  --lang=en or --english    : English"
echo "  --lang=ja or --japanese   : Japanese"
echo "  -l en                     : English (short form)"
echo "  -l ja                     : Japanese (short form)"
echo "  (no option)               : Auto-detect from system"
