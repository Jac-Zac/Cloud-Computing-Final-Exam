#!/bin/bash

# Modified install-deps.sh to fix the filename typo
set -e

echo "📦 Installing dependencies..."

# Check the system type
if [[ "$(uname)" == "Darwin" ]]; then
    echo "🍎 macOS detected - using Homebrew for installation"
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        echo "❌ Homebrew not found. Please install Homebrew first:"
        echo "   /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
    
    # Install macOS dependencies
    brew install sysbench iozone iperf3 stress-ng
    brew install open-mpi
    echo "Note: HPCC may not be available on macOS via brew. MPI tests may be limited."
    
elif [[ "$(uname)" == "Linux" ]]; then
    echo "🐧 Linux detected - using apt for installation"
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        SUDO="sudo"
        echo "Using sudo for installation"
    else
        SUDO=""
    fi
    
    $SUDO apt update
    $SUDO apt install -y sysbench iozone3 iperf3 mpich stress-ng
    
    # Try to install HPCC if available
    if $SUDO apt-cache search hpcc | grep -q "^hpcc "; then
        $SUDO apt install -y hpcc
    else
        echo "⚠️ HPCC package not found. HPL benchmarks might not work."
        echo "   Consider installing from source if needed."
    fi
else
    echo "❌ Unsupported operating system: $(uname)"
    echo "   Please install dependencies manually:"
    echo "   - sysbench"
    echo "   - iozone"
    echo "   - iperf3"
    echo "   - stress-ng"
    echo "   - MPI implementation (mpich or open-mpi)"
    echo "   - HPCC (if available)"
    exit 1
fi

echo "✅ Dependencies installed successfully."
