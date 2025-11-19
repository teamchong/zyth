#!/bin/bash
# Hyperfine benchmark comparison: Zig vs Rust

set -e

echo "🔥 Building production releases..."
echo "=================================="

# Build Zig (ReleaseFast)
echo "Building Zig tokenizer..."
zig build --release=fast
zig_bin="./zig-out/bin/tokenizer_bench"

# Build Rust (release)
echo "Building Rust tokenizer..."
cd benchmark_rust
cargo build --release
rust_bin="./target/release/bench"
cd ..

echo ""
echo "🚀 Running hyperfine benchmarks..."
echo "=================================="

# Check if hyperfine is installed
if ! command -v hyperfine &> /dev/null; then
    echo "❌ hyperfine not found. Install with:"
    echo "   brew install hyperfine  # macOS"
    echo "   cargo install hyperfine  # Rust"
    exit 1
fi

# Run comparison
hyperfine \
    --warmup 3 \
    --runs 10 \
    --export-markdown bench_results.md \
    --export-json bench_results.json \
    "$zig_bin" \
    "./benchmark_rust/$rust_bin"

echo ""
echo "📊 Results saved to:"
echo "  - bench_results.md   (Markdown table)"
echo "  - bench_results.json (JSON data)"
echo ""
echo "✨ Benchmark complete!"
