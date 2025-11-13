.PHONY: help build install verify test test-zig format-zig lint-zig clean run benchmark

help:
	@echo "Zyth Commands"
	@echo "============="
	@echo "install        - Build optimized binary and install to ~/.local/bin (RECOMMENDED)"
	@echo "build          - Build debug binary for development"
	@echo "build-release  - Build optimized production binary"
	@echo "verify         - Verify installation is working"
	@echo "test           - Run pytest regression tests"
	@echo "test-zig       - Run Zig runtime tests"
	@echo "format-zig     - Format Zig code"
	@echo "lint-zig       - Check Zig code formatting"
	@echo "clean          - Remove build artifacts"

build:
	@echo "🔨 Building zyth compiler (debug mode)..."
	@command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed"; exit 1; }
	zig build
	@echo "✅ Debug binary built: zig-out/bin/zyth"

build-release:
	@echo "🔨 Building zyth compiler (optimized for production)..."
	@command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed"; exit 1; }
	zig build -Doptimize=ReleaseSafe
	@echo "✅ Release binary built: zig-out/bin/zyth"

install: build-release
	@echo "📦 Installing zyth to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	@cp zig-out/bin/zyth ~/.local/bin/zyth
	@chmod +x ~/.local/bin/zyth
	@echo ""
	@echo "✅ Zyth installed!"
	@echo ""
	@echo "Make sure ~/.local/bin is in your PATH:"
	@echo "  export PATH=\"\$$HOME/.local/bin:\$$PATH\""
	@echo ""
	@echo "Then run: zyth your_file.py"
	@echo ""

verify:
	@bash scripts/verify-install.sh

test:
	@echo "🧪 Running regression tests..."
	pytest tests/test_regression.py -v
	@echo "✅ Tests complete"

test-zig:
	@echo "🧪 Running Zig runtime tests..."
	zig test packages/runtime/src/runtime.zig
	@echo "✅ Zig runtime tests passed"

format-zig:
	@echo "🎨 Formatting Zig code..."
	@zig fmt src/*.zig
	@zig fmt packages/runtime/src/*.zig
	@echo "✅ Zig code formatted"

lint-zig:
	@echo "🔍 Checking Zig formatting..."
	@zig fmt --check src/*.zig
	@zig fmt --check packages/runtime/src/*.zig
	@echo "✅ Zig formatting OK"

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".mypy_cache" -exec rm -rf {} + 2>/dev/null || true
	rm -rf bin/ output fib_binary test_output

run:
	@echo "⚠️  DEPRECATED: Use 'zyth' command directly instead"
	@echo "    New: zyth $(FILE)"
	@echo ""
	uv run zyth $(FILE)

benchmark:
	uv run python _prototype/benchmark.py
