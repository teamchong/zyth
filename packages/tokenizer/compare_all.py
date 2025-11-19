#!/usr/bin/env python3
"""
Fair comparison: Rust vs PyAOT Zig vs Python libraries
Using EXACT same data (15K texts, vocab 2048, 3K encoding iterations)
"""

import subprocess
import sys
import re

def run_zig_benchmark():
    """Run Zig benchmark and parse output"""
    print("\n🔥 Running PyAOT Zig benchmark...")
    result = subprocess.run(
        ["./zig-out/bin/tokenizer_bench"],
        capture_output=True,
        text=True,
        timeout=120
    )

    output = result.stdout

    # Parse training time
    train_match = re.search(r"Training time: (\d+)ms", output)
    train_ms = int(train_match.group(1)) if train_match else None

    # Parse encoding time
    encode_match = re.search(r"(\d+) iterations: (\d+)ms total", output)
    encode_ms = int(encode_match.group(2)) if encode_match else None

    if not train_ms or not encode_ms:
        print(f"  ⚠️  Failed to parse. Output:\n{output[:500]}")

    print(f"  Training: {train_ms}ms")
    print(f"  Encoding (3000 iters): {encode_ms}ms")
    print(f"  Total: {train_ms + encode_ms if train_ms and encode_ms else 'N/A'}ms")

    return {
        "name": "PyAOT Zig",
        "train_ms": train_ms,
        "encode_ms": encode_ms,
        "total_ms": train_ms + encode_ms if train_ms and encode_ms else None
    }


def run_rust_benchmark():
    """Run Rust benchmark and parse output"""
    print("\n🦀 Running Rust benchmark...")
    result = subprocess.run(
        ["./benchmark_rust/target/release/bench"],
        capture_output=True,
        text=True,
        timeout=120
    )

    output = result.stdout

    # Parse training time
    train_match = re.search(r"Training time: (\d+)ms", output)
    train_ms = int(train_match.group(1)) if train_match else None

    # Parse encoding time
    encode_match = re.search(r"Total time \((\d+) iterations\): (\d+)ms", output)
    encode_ms = int(encode_match.group(2)) if encode_match else None

    print(f"  Training: {train_ms}ms")
    print(f"  Encoding (3000 iters): {encode_ms}ms")
    print(f"  Total: {train_ms + encode_ms if train_ms and encode_ms else 'N/A'}ms")

    return {
        "name": "Rust rustbpe",
        "train_ms": train_ms,
        "encode_ms": encode_ms,
        "total_ms": train_ms + encode_ms if train_ms and encode_ms else None
    }


def benchmark_huggingface():
    """HuggingFace with SAME workload"""
    try:
        from tokenizers import Tokenizer
        from tokenizers.models import BPE
        from tokenizers.trainers import BpeTrainer
        from tokenizers.pre_tokenizers import Whitespace
        import time
    except ImportError:
        print("\n❌ HuggingFace tokenizers not installed")
        return None

    print("\n🤗 Running HuggingFace benchmark...")

    # Same data as Zig/Rust
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
    TEST_TEXT = (
        "The quick brown fox jumps over the lazy dog. "
        "This sentence contains every letter of the alphabet at least once. "
        "Machine learning models process text by converting it to tokens. "
        "Byte pair encoding learns frequent subword units from training data. "
        "Modern language models use BPE tokenization for efficiency."
    )

    # Training
    tokenizer = Tokenizer(BPE(unk_token="[UNK]"))
    tokenizer.pre_tokenizer = Whitespace()
    trainer = BpeTrainer(vocab_size=2048, special_tokens=["[UNK]"])

    train_start = time.perf_counter()
    tokenizer.train_from_iterator(TRAINING_TEXTS, trainer=trainer)
    train_ms = (time.perf_counter() - train_start) * 1000

    # Encoding (30000 iterations - same as Zig/Rust)
    encode_start = time.perf_counter()
    for _ in range(30000):
        output = tokenizer.encode(TEST_TEXT)
    encode_ms = (time.perf_counter() - encode_start) * 1000

    print(f"  Training: {train_ms:.0f}ms")
    print(f"  Encoding (30000 iters): {encode_ms:.0f}ms")
    print(f"  Total: {train_ms + encode_ms:.0f}ms")

    return {
        "name": "HuggingFace",
        "train_ms": train_ms,
        "encode_ms": encode_ms,
        "total_ms": train_ms + encode_ms
    }


def benchmark_tiktoken():
    """tiktoken encoding only (no training)"""
    try:
        import tiktoken
        import time
    except ImportError:
        print("\n❌ tiktoken not installed")
        return None

    print("\n⚡ Running tiktoken benchmark...")

    TEST_TEXT = (
        "The quick brown fox jumps over the lazy dog. "
        "This sentence contains every letter of the alphabet at least once. "
        "Machine learning models process text by converting it to tokens. "
        "Byte pair encoding learns frequent subword units from training data. "
        "Modern language models use BPE tokenization for efficiency."
    )

    enc = tiktoken.get_encoding("cl100k_base")

    # Encoding only (30000 iterations - same as others)
    encode_start = time.perf_counter()
    for _ in range(30000):
        tokens = enc.encode(TEST_TEXT)
    encode_ms = (time.perf_counter() - encode_start) * 1000

    print(f"  Training: N/A (pre-trained)")
    print(f"  Encoding (30000 iters): {encode_ms:.0f}ms")
    print(f"  Total: N/A (encoding only)")

    return {
        "name": "tiktoken",
        "train_ms": None,
        "encode_ms": encode_ms,
        "total_ms": None
    }


def print_comparison(results):
    """Print final comparison table"""
    print("\n" + "=" * 80)
    print("📊 FINAL RESULTS - Same Data (15K texts, vocab 2048, 3K encoding)")
    print("=" * 80)
    print()
    print(f"{'Implementation':<20} {'Training':<15} {'Encoding':<15} {'Total':<15} {'vs Winner':<15}")
    print("-" * 80)

    valid = [r for r in results if r and r['total_ms']]
    sorted_results = sorted(valid, key=lambda x: x['total_ms'])

    winner_total = sorted_results[0]['total_ms'] if sorted_results else None

    for r in results:
        if r:
            train = f"{r['train_ms']:.0f}ms" if r['train_ms'] else "N/A"
            encode = f"{r['encode_ms']:.0f}ms" if r['encode_ms'] else "N/A"
            total = f"{r['total_ms']:.0f}ms" if r['total_ms'] else "N/A"

            if r['total_ms'] and winner_total:
                ratio = r['total_ms'] / winner_total
                vs_winner = f"{ratio:.2f}x"
            else:
                vs_winner = "N/A"

            print(f"{r['name']:<20} {train:<15} {encode:<15} {total:<15} {vs_winner:<15}")

    print("-" * 80)

    if sorted_results:
        winner = sorted_results[0]
        print(f"\n🏆 WINNER: {winner['name']} ({winner['total_ms']:.0f}ms total)")

    print()


def main():
    print("=" * 80)
    print("🔥 COMPREHENSIVE BPE TOKENIZER BENCHMARK")
    print("=" * 80)
    print()
    print("Workload: 15,000 texts, vocab 2048, 3,000 encoding iterations")
    print("Platform: macOS ARM64 (Apple Silicon)")
    print()

    results = []

    # Run all benchmarks
    try:
        results.append(run_zig_benchmark())
    except Exception as e:
        print(f"  ❌ Zig benchmark failed: {e}")

    try:
        results.append(run_rust_benchmark())
    except Exception as e:
        print(f"  ❌ Rust benchmark failed: {e}")

    results.append(benchmark_huggingface())
    results.append(benchmark_tiktoken())

    # Show comparison
    print_comparison(results)

    print("=" * 80)
    print("✨ Benchmark complete!")
    print()


if __name__ == "__main__":
    main()
