#!/bin/bash
# Verify PyAOT installation

set -e

echo "🔍 Verifying PyAOT installation..."
echo ""

# Check pyaot command exists
if command -v pyaot >/dev/null 2>&1; then
    echo "✅ pyaot command found in PATH"
else
    echo "❌ pyaot command not found"
    echo "   Run: source .venv/bin/activate"
    exit 1
fi

# Test help
echo "✅ Testing --help..."
pyaot --help >/dev/null

# Test compilation
echo "✅ Testing compilation..."
pyaot examples/fibonacci.py -o /tmp/pyaot_verify_test >/dev/null 2>&1

# Test execution
echo "✅ Testing execution..."
OUTPUT=$(/tmp/pyaot_verify_test 2>&1)
if [ "$OUTPUT" = "55" ]; then
    echo "✅ Output correct: $OUTPUT"
else
    echo "❌ Output incorrect: '$OUTPUT' (expected '55')"
    exit 1
fi

# Clean up
rm -f /tmp/pyaot_verify_test

echo ""
echo "✅ All checks passed! PyAOT is properly installed."
echo ""
echo "Try: pyaot examples/fibonacci.py --run"
echo ""
