#!/usr/bin/env python3
"""
Quick benchmark: PyAOT vs TokenDagger only
For fast iteration during optimization
"""
import subprocess
import sys

TEXT = """The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow."""

print("⚡ Quick Benchmark: PyAOT vs TokenDagger")
print("=" * 60)
print(f"Text: {len(TEXT)} bytes")
print(f"Iterations: 60,000")
print()

# TokenDagger baseline
print("1. TokenDagger (C baseline)...")
try:
    result = subprocess.run(
        ['python3', 'bench_tokendagger.py'],
        capture_output=True,
        text=True,
        timeout=30
    )

    # Parse simple output: "477ms\n"
    tokendagger_ms = int(result.stdout.strip().replace('ms', ''))
    print(f"   Time: {tokendagger_ms}ms")
except Exception as e:
    print(f"   ERROR: {e}")
    tokendagger_ms = 477  # Use known baseline

print()

# PyAOT
print("2. PyAOT (Zig)...")
try:
    result = subprocess.run(
        ['./zig-out/bin/bench_native'],
        capture_output=True,
        text=True,
        timeout=30
    )

    # Parse simple output from stderr: "392ms\n"
    output = result.stderr if result.stderr else result.stdout
    pyaot_ms = int(output.strip().replace('ms', ''))
    print(f"   Time: {pyaot_ms}ms")
        
except subprocess.TimeoutExpired:
    print("   ❌ TIMEOUT - PyAOT hung (likely bug in optimization)")
    sys.exit(1)
except Exception as e:
    print(f"   ERROR: {e}")
    sys.exit(1)

print()
print("=" * 60)
print("📊 RESULTS")
print("=" * 60)

# Compare
if pyaot_ms < tokendagger_ms:
    speedup = tokendagger_ms / pyaot_ms
    improvement = tokendagger_ms - pyaot_ms
    print(f"🏆 PyAOT WINS: {pyaot_ms}ms vs {tokendagger_ms}ms")
    print(f"   {speedup:.2f}x faster ({improvement}ms improvement)")
else:
    slowdown = pyaot_ms / tokendagger_ms
    gap = pyaot_ms - tokendagger_ms
    print(f"TokenDagger: {tokendagger_ms}ms 🏆")
    print(f"PyAOT:       {pyaot_ms}ms")
    print(f"   {slowdown:.2f}x slower ({gap}ms gap to close)")

print()
