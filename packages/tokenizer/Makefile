.PHONY: help benchmark benchmark-train benchmark-encoding benchmark-web benchmark-quick build clean

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RESET := \033[0m

# Default target - show help
help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)PyAOT Tokenizer Benchmarks$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@echo "$(GREEN)Available targets:$(RESET)"
	@echo "  make benchmark          - Run all benchmarks (train + encoding + web)"
	@echo "  make benchmark-quick    - PyAOT vs TokenDagger only (fast iteration)"
	@echo "  make benchmark-train    - BPE training (3 libraries, 150K texts)"
	@echo "  make benchmark-encoding - Native encoding (2 libraries, 60K iterations)"
	@echo "  make benchmark-web      - Browser (5 libraries, 10K iterations)"
	@echo ""
	@echo "$(GREEN)Build targets:$(RESET)"
	@echo "  make build              - Build native tokenizer"
	@echo "  make build-wasm         - Build WASM tokenizer"
	@echo "  make clean              - Clean build artifacts"
	@echo ""

# Run all benchmarks
benchmark: benchmark-train benchmark-encoding benchmark-web

# Training benchmarks (PyAOT vs HuggingFace vs SentencePiece)
benchmark-train:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)📊 BPE Training Benchmark (150K texts, vocab 2048)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 bench_training.py
	@echo ""

# Quick benchmark (PyAOT vs TokenDagger only - for fast iteration)
benchmark-quick: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)⚡ Quick Benchmark: PyAOT vs TokenDagger (hyperfine)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@./bench_hyperfine.sh
	@echo ""

# Native encoding benchmarks (PyAOT vs tiktoken - 60K iterations)
benchmark-encoding: build
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)⚡ Native Encoding Benchmark (60K iterations)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@python3 final_benchmark.py
	@echo ""

# Browser benchmarks (5 libraries - 10K iterations each)
benchmark-web: build-wasm
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo "$(GREEN)🌐 Browser Tokenizer Benchmark (10K iterations)$(RESET)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(RESET)"
	@echo ""
	@if ! python3 -c "import playwright" 2>/dev/null; then \
		echo "$(YELLOW)⚠️  Installing playwright...$(RESET)"; \
		pip install playwright && playwright install chromium; \
	fi
	@python3 run_browser_benchmark.py
	@echo ""

# Build native tokenizer
build:
	@echo "$(YELLOW)🔨 Building native tokenizer...$(RESET)"
	@zig build --release=fast
	@zig build-exe src/bench_native.zig -O ReleaseFast
	@mv bench_native zig-out/bin/
	@echo "$(GREEN)✅ Build complete$(RESET)"
	@echo ""

# Build WASM tokenizer
build-wasm:
	@echo "$(YELLOW)🔨 Building WASM tokenizer...$(RESET)"
	@mkdir -p dist
	@zig build-lib src/wasm.zig -target wasm32-freestanding -O ReleaseFast -dynamic
	@mv wasm.wasm dist/pyaot_tokenizer.wasm
	@if [ ! -f dist/cl100k_simple.json ]; then \
		echo "$(YELLOW)⚠️  cl100k_simple.json not found in dist/$(RESET)"; \
		echo "$(YELLOW)   Copy vocab file: cp vocab/cl100k_simple.json dist/$(RESET)"; \
		exit 1; \
	fi
	@echo "$(GREEN)✅ WASM build complete$(RESET)"
	@echo ""

# Clean build artifacts
clean:
	@echo "$(YELLOW)🧹 Cleaning build artifacts...$(RESET)"
	@rm -rf zig-out/ zig-cache/ dist/*.wasm
	@rm -f bench_trainer bench_cl100k test_tokendagger
	@rm -f *.a *.o
	@echo "$(GREEN)✅ Clean complete$(RESET)"
