.PHONY: help install install-dev install-cli verify test test-zig lint format typecheck clean run benchmark

help:
	@echo "Zyth Development Commands"
	@echo "========================="
	@echo "install-dev - Full development setup (recommended first step)"
	@echo "install     - Install workspace packages only"
	@echo "install-cli - Install CLI to make 'zyth' command available"
	@echo "verify      - Verify installation is working"
	@echo "test        - Run Python tests"
	@echo "test-zig    - Run Zig runtime tests"
	@echo "lint        - Run linter"
	@echo "format      - Format code"
	@echo "typecheck   - Run type checker"
	@echo "clean       - Remove build artifacts"
	@echo "run         - Run example (make run FILE=examples/fibonacci.py) [DEPRECATED: use 'zyth' command]"
	@echo "benchmark   - Run performance benchmarks"

install-dev:
	@echo "🔧 Setting up Zyth development environment..."
	@command -v uv >/dev/null 2>&1 || { echo "❌ Error: uv not installed"; exit 1; }
	@command -v zig >/dev/null 2>&1 || { echo "❌ Error: zig not installed"; exit 1; }
	uv sync
	uv pip install -e packages/core -e packages/runtime -e packages/cli -e packages/web -e packages/http -e packages/ai -e packages/async -e packages/db
	@echo ""
	@echo "✅ Development environment ready!"
	@echo ""
	@echo "To use 'zyth' command, activate the virtual environment:"
	@echo "  source .venv/bin/activate"
	@echo ""
	@echo "Or use: uv run zyth examples/fibonacci.py"
	@echo ""

install:
	uv sync

install-cli:
	uv pip install -e packages/cli
	@echo ""
	@echo "✅ CLI installed! Activate venv to use:"
	@echo "  source .venv/bin/activate"
	@echo "  zyth --help"
	@echo ""

verify:
	@bash scripts/verify-install.sh

test:
	uv run pytest packages/*/tests -v

test-zig:
	zig test packages/runtime/src/runtime.zig
	@echo "✅ Zig runtime tests passed"

lint:
	uv run ruff check packages/

format:
	uv run ruff format packages/

typecheck:
	uv run mypy packages/

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
