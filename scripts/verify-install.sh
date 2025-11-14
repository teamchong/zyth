#!/bin/bash
# Verify PyX installation

set -e

echo "🔍 Verifying PyX installation..."
echo ""

# Check pyx command exists
if command -v pyx >/dev/null 2>&1; then
    echo "✅ pyx command found in PATH"
else
    echo "❌ pyx command not found"
    echo "   Run: source .venv/bin/activate"
    exit 1
fi

# Test help
echo "✅ Testing --help..."
pyx --help >/dev/null

# Test compilation
echo "✅ Testing compilation..."
pyx examples/fibonacci.py -o /tmp/pyx_verify_test >/dev/null 2>&1

# Test execution
echo "✅ Testing execution..."
OUTPUT=$(/tmp/pyx_verify_test 2>&1)
if [ "$OUTPUT" = "55" ]; then
    echo "✅ Output correct: $OUTPUT"
else
    echo "❌ Output incorrect: '$OUTPUT' (expected '55')"
    exit 1
fi

# Clean up
rm -f /tmp/pyx_verify_test

echo ""
echo "✅ All checks passed! PyX is properly installed."
echo ""
echo "Try: pyx examples/fibonacci.py --run"
echo ""
