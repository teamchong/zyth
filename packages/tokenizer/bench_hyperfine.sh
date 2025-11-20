#!/bin/bash
# Hyperfine benchmark: PyAOT vs TokenDagger

set -e

echo "⚡ Hyperfine Benchmark: PyAOT vs TokenDagger"
echo "============================================================"

# Build if needed
if [ ! -f zig-out/bin/bench_native ]; then
    echo "Building bench_native..."
    zig build-exe src/bench_native.zig -O ReleaseFast
    mv bench_native zig-out/bin/
fi

# Run hyperfine
hyperfine \
    --warmup 3 \
    --runs 10 \
    --export-markdown bench_quick_results.md \
    --command-name "PyAOT (Zig)" './zig-out/bin/bench_native' \
    --command-name "TokenDagger (C)" 'python3 bench_tokendagger.py'

echo ""
echo "📊 Results saved to bench_quick_results.md"
