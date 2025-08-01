#!/bin/bash

# Amazon Linux 2用のビルドスクリプト

echo "========================================="
echo " Building countdown for Amazon Linux 2"
echo "========================================="

# コンパイラの確認
if ! command -v gcc &> /dev/null; then
    echo "Error: GCC not found. Installing GCC..."
    sudo yum install -y gcc
    if [ $? -ne 0 ]; then
        echo "Failed to install GCC. Please install manually:"
        echo "sudo yum install -y gcc"
        exit 1
    fi
fi

echo "Building countdown with internationalization support..."

# Amazon Linux 2向けコンパイル
gcc -o countdown-linux countdown-linux.c -lpthread
if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo ""
    
    echo "Testing with default language (auto-detect):"
    ./countdown-linux 3
    echo ""
    
    echo "Testing with English:"
    ./countdown-linux --lang=en 3
    echo ""
    
    echo "Testing with Japanese:"
    ./countdown-linux --lang=ja 3
    echo ""
    
    echo "Available language options:"
    echo "  --lang=en or --english    : English"
    echo "  --lang=ja or --japanese   : Japanese"
    echo "  -l en                     : English (short form)"
    echo "  -l ja                     : Japanese (short form)"
    echo "  (no option)               : Auto-detect from system"
    echo ""
    echo "Executable created: countdown-linux"
else
    echo "❌ Build failed!"
    exit 1
fi
