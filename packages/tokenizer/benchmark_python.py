#!/usr/bin/env python3
"""
BPE Tokenizer Benchmark: Rust vs PyAOT Zig vs Fastest Python Libraries

Compares:
- PyAOT Zig tokenizer (our implementation)
- Rust rustbpe baseline
- rs-bpe (fastest Python BPE)
- tiktoken (OpenAI standard)
- HuggingFace tokenizers (most popular)
"""

import time
import sys
import subprocess

# Same workload as Zig/Rust benchmarks
BASE_TEXTS = [
    "Hello world! This is a test.",
    "The quick brown fox jumps over the lazy dog.",
    "Machine learning and natural language processing.",
    "Byte pair encoding is a text tokenization method.",
    "This is a longer text to make training more interesting.",
    "Neural networks learn from large amounts of training data.",
    "Tokenization breaks text into smaller units called tokens.",
    "Python is a popular programming language for data science.",
    "Deep learning models require significant computational resources.",
    "Natural language understanding is a challenging AI problem.",
    "Transformers revolutionized the field of NLP in recent years.",
    "GPT models demonstrate impressive text generation capabilities.",
    "Byte pair encoding creates subword vocabularies efficiently.",
    "Machine translation systems bridge communication across languages.",
    "Sentiment analysis determines emotional tone in text.",
]

TRAINING_TEXTS = BASE_TEXTS * 1000  # 15,000 texts
VOCAB_SIZE = 2048
ENCODE_ITERATIONS = 3000

TEST_TEXT = (
    "The quick brown fox jumps over the lazy dog. "
    "This sentence contains every letter of the alphabet at least once. "
    "Machine learning models process text by converting it to tokens. "
    "Byte pair encoding learns frequent subword units from training data. "
    "Modern language models use BPE tokenization for efficiency."
)


def benchmark_rs_bpe():
    """rs-bpe - Fastest Python BPE (March 2025)"""
    try:
        from rs_bpe import RsBpeTokenizer
    except ImportError:
        print("❌ rs-bpe not installed: pip install rs-bpe")
        return None

    print("\n⚡ rs-bpe (Fastest Python BPE)")
    print("-" * 60)

    train_start = time.perf_counter()
    tokenizer = RsBpeTokenizer.train(TRAINING_TEXTS, vocab_size=VOCAB_SIZE)
    train_ms = (time.perf_counter() - train_start) * 1000

    # Warmup
    for _ in range(10):
        tokenizer.encode(TEST_TEXT)

    encode_start = time.perf_counter()
    for _ in range(ENCODE_ITERATIONS):
        tokens = tokenizer.encode(TEST_TEXT)
    encode_ms = (time.perf_counter() - encode_start) * 1000

    per_iter_us = encode_ms * 1000 / ENCODE_ITERATIONS

    print(f"  Training: {train_ms:.0f}ms")
    print(f"  Encoding ({ENCODE_ITERATIONS} iters): {encode_ms:.0f}ms")
    print(f"  Per iteration: {per_iter_us:.0f}μs")
    print(f"  Tokens: {len(tokens)}")

    return {
        "name": "rs-bpe",
        "train_ms": train_ms,
        "encode_ms": encode_ms,
        "per_iter_us": per_iter_us,
    }


def benchmark_tiktoken():
    """tiktoken - OpenAI standard (pre-trained only)"""
    try:
        import tiktoken
    except ImportError:
        print("❌ tiktoken not installed: pip install tiktoken")
        return None

    print("\n🔥 tiktoken (OpenAI)")
    print("-" * 60)

    enc = tiktoken.get_encoding("cl100k_base")

    # Warmup
    for _ in range(10):
        enc.encode(TEST_TEXT)

    encode_start = time.perf_counter()
    for _ in range(ENCODE_ITERATIONS):
        tokens = enc.encode(TEST_TEXT)
    encode_ms = (time.perf_counter() - encode_start) * 1000

    per_iter_us = encode_ms * 1000 / ENCODE_ITERATIONS

    print(f"  Training: N/A (pre-trained cl100k_base)")
    print(f"  Encoding ({ENCODE_ITERATIONS} iters): {encode_ms:.0f}ms")
    print(f"  Per iteration: {per_iter_us:.0f}μs")
    print(f"  Tokens: {len(tokens)}")

    return {
        "name": "tiktoken",
        "train_ms": None,
        "encode_ms": encode_ms,
        "per_iter_us": per_iter_us,
    }


def benchmark_huggingface():
    """HuggingFace tokenizers - Most popular"""
    try:
        from tokenizers import Tokenizer
        from tokenizers.models import BPE
        from tokenizers.trainers import BpeTrainer
        from tokenizers.pre_tokenizers import Whitespace
    except ImportError:
        print("❌ tokenizers not installed: pip install tokenizers")
        return None

    print("\n🤗 HuggingFace tokenizers")
    print("-" * 60)

    tokenizer = Tokenizer(BPE(unk_token="[UNK]"))
    tokenizer.pre_tokenizer = Whitespace()
    trainer = BpeTrainer(vocab_size=VOCAB_SIZE, special_tokens=["[UNK]"])

    train_start = time.perf_counter()
    tokenizer.train_from_iterator(TRAINING_TEXTS, trainer=trainer)
    train_ms = (time.perf_counter() - train_start) * 1000

    # Warmup
    for _ in range(10):
        tokenizer.encode(TEST_TEXT)

    encode_start = time.perf_counter()
    for _ in range(ENCODE_ITERATIONS):
        output = tokenizer.encode(TEST_TEXT)
        tokens = output.ids
    encode_ms = (time.perf_counter() - encode_start) * 1000

    per_iter_us = encode_ms * 1000 / ENCODE_ITERATIONS

    print(f"  Training: {train_ms:.0f}ms")
    print(f"  Encoding ({ENCODE_ITERATIONS} iters): {encode_ms:.0f}ms")
    print(f"  Per iteration: {per_iter_us:.0f}μs")
    print(f"  Tokens: {len(tokens)}")

    return {
        "name": "huggingface",
        "train_ms": train_ms,
        "encode_ms": encode_ms,
        "per_iter_us": per_iter_us,
    }


def get_native_benchmarks():
    """Get Zig and Rust benchmark results from bench_results.md"""
    try:
        with open("bench_results.md", "r") as f:
            lines = f.readlines()

        # Parse markdown table
        zig_time = None
        rust_time = None

        for line in lines:
            if "tokenizer_bench" in line:
                parts = line.split("|")
                if len(parts) >= 3:
                    zig_time = float(parts[1].strip().split()[0])
            elif "rust" in line.lower() and "bench" in line:
                parts = line.split("|")
                if len(parts) >= 3:
                    rust_time = float(parts[1].strip().split()[0])

        results = []
        if zig_time:
            results.append({
                "name": "PyAOT Zig",
                "train_ms": None,
                "encode_ms": zig_time * 1000,
                "per_iter_us": None,
            })
        if rust_time:
            results.append({
                "name": "Rust rustbpe",
                "train_ms": None,
                "encode_ms": rust_time * 1000,
                "per_iter_us": None,
            })

        return results
    except:
        return []


def print_results(results):
    """Print comparison table"""
    print("\n" + "=" * 80)
    print("📊 FINAL BENCHMARK RESULTS")
    print("=" * 80)
    print()
    print(f"{'Implementation':<25} {'Total (ms)':<15} {'Training (ms)':<15} {'Encoding (ms)':<15}")
    print("-" * 80)

    # Sort by total time (encoding only, or training+encoding)
    valid_results = [r for r in results if r]
    sorted_results = sorted(valid_results, key=lambda x: x["encode_ms"] or float('inf'))

    for r in sorted_results:
        train = f"{r['train_ms']:.0f}" if r['train_ms'] else "N/A"
        encode = f"{r['encode_ms']:.0f}" if r['encode_ms'] else "N/A"
        total = r['encode_ms'] if r['encode_ms'] else 0
        if r['train_ms']:
            total += r['train_ms']

        print(f"{r['name']:<25} {total:<15.0f} {train:<15} {encode:<15}")

    print("-" * 80)
    print()

    # Highlight winner
    if sorted_results:
        winner = sorted_results[0]
        print(f"🏆 WINNER: {winner['name']} ({winner['encode_ms']:.0f}ms)")
        print()

        # Show speedup vs others
        print("Speedup vs others:")
        for r in sorted_results[1:]:
            if r['encode_ms']:
                speedup = r['encode_ms'] / winner['encode_ms']
                print(f"  {r['name']:<25} {speedup:.2f}x slower")

    print()


def main():
    print("=" * 80)
    print("🔥 ULTIMATE BPE TOKENIZER BENCHMARK")
    print("=" * 80)
    print()
    print("Comparing:")
    print("  • PyAOT Zig tokenizer (our ultra-optimized implementation)")
    print("  • Rust rustbpe baseline")
    print("  • rs-bpe (fastest Python BPE, March 2025)")
    print("  • tiktoken (OpenAI standard)")
    print("  • HuggingFace tokenizers (most popular)")
    print()
    print(f"Workload: {len(TRAINING_TEXTS)} texts, vocab {VOCAB_SIZE}, {ENCODE_ITERATIONS} encoding iterations")
    print()

    results = []

    # Get native benchmarks (Zig + Rust)
    print("📖 Reading native benchmark results...")
    native = get_native_benchmarks()
    if native:
        for r in native:
            print(f"  ✅ {r['name']}: {r['encode_ms']:.0f}ms")
        results.extend(native)
    else:
        print("  ⚠️  Could not read bench_results.md")
        print("  Run ./bench.sh first to get Zig/Rust results")

    # Python benchmarks
    results.append(benchmark_rs_bpe())
    results.append(benchmark_tiktoken())
    results.append(benchmark_huggingface())

    # Final comparison
    print_results(results)

    print("=" * 80)
    print("✨ Benchmark complete!")
    print()
    print("Install missing libraries:")
    print("  pip install rs-bpe tiktoken tokenizers")
    print()


if __name__ == "__main__":
    main()
