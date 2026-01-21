#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/resources/bin"

echo "Building FnKeyHelper..."
echo "Script dir: $SCRIPT_DIR"
echo "Output dir: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Build with Swift Package Manager
cd "$SCRIPT_DIR"

# Build for release
swift build -c release

# Copy binary to resources
cp .build/release/FnKeyHelper "$OUTPUT_DIR/FnKeyHelper"

# Make executable
chmod +x "$OUTPUT_DIR/FnKeyHelper"

echo "Build complete: $OUTPUT_DIR/FnKeyHelper"

# Verify binary
echo ""
echo "Binary info:"
file "$OUTPUT_DIR/FnKeyHelper"
echo ""
echo "Size: $(du -h "$OUTPUT_DIR/FnKeyHelper" | cut -f1)"
