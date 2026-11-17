#!/bin/sh
# Compile the app-windows helper next to this script's parent folder: bin/app-windows
# Needs the Xcode command line tools (xcode-select --install).
set -e
here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$here/../bin"
swiftc -O "$here/app-windows.swift" -o "$here/../bin/app-windows"
echo "built $here/../bin/app-windows"
