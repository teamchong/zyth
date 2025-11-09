# Zyth

Python to Zig compiler. Write Python, run native code.

**Up to 41x faster** than CPython | Native binaries | Zero interpreter overhead

## Quick Start

```bash
# Clone and setup
git clone <repo-url> zyth
cd zyth
make install-dev

# Activate environment
source .venv/bin/activate

# Compile and run
zyth examples/fibonacci.py --run
```

## Installation

### Development Setup (Contributors)

```bash
make install-dev
source .venv/bin/activate
zyth --help
```

### Production Install (Users)

```bash
# From PyPI (when published)
pip install zyth-cli
zyth --help

# Or with pipx (isolated)
pipx install zyth-cli
```

### Manual Install

```bash
# From source
uv pip install -e packages/cli

# Activate venv
source .venv/bin/activate
zyth --help
```

## Usage

```bash
# Compile Python to native binary
zyth app.py

# Compile and run immediately
zyth app.py --run

# Specify output path
zyth app.py -o my_binary

# Show generated Zig code
zyth app.py --show-zig
```

## Example

**Input (examples/fibonacci.py):**
```python
def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

result = fibonacci(10)
print(result)
```

**Compile:**
```bash
zyth examples/fibonacci.py -o fib
./fib
# Output: 55
```

## Performance

| Benchmark | CPython | Zyth | Speedup |
|:---|---:|---:|---:|
| **Loop sum (1M)** | 65.4 ms | 1.6 ms | **41.40x faster** 🔥 |
| **Fibonacci(35)** | 804.5 ms | 28.2 ms | **28.56x faster** 🚀 |
| **String concat** | 23.6 ms | 1.9 ms | **12.24x faster** ⚡ |

**Benchmarked with [hyperfine](https://github.com/sharkdp/hyperfine)** on macOS ARM64.

Raw results: [loop_sum_results.md](benchmarks/loop_sum_results.md) · [fibonacci_results.md](benchmarks/fibonacci_results.md) · [string_results.md](benchmarks/string_results.md)

## Features

**Current:**
- ✅ Function definitions with type hints
- ✅ Integer arithmetic and recursion
- ✅ String operations (concatenation, literals)
- ✅ Control flow (if/else, while, for/range)
- ✅ Variable reassignment detection (var vs const)
- ✅ Binary compilation to native code
- ✅ 41x+ performance improvement

**Roadmap:**
- [ ] Lists and dicts (runtime ready, codegen needed)
- [ ] String methods (.upper(), .lower())
- [ ] Classes and methods
- [ ] Standard library (zyth.web, zyth.http, zyth.ai)
- [ ] WebAssembly target
- [ ] Goroutines and channels

## Project Structure

```
zyth/
├── packages/
│   ├── core/       # Compiler (parser, codegen)
│   ├── runtime/    # Zig runtime library
│   ├── cli/        # Command-line tool
│   ├── web/        # zyth.web (future)
│   ├── http/       # zyth.http (future)
│   └── ai/         # zyth.ai (future)
├── examples/       # Example programs
└── docs/          # Documentation
```

## Development

```bash
# Run tests
make test         # Python tests
make test-zig     # Zig runtime tests

# Code quality
make lint         # Run linter
make format       # Format code
make typecheck    # Type check

# Run example
make run FILE=examples/fibonacci.py

# Clean build artifacts
make clean
```

## Requirements

- Python 3.10+
- Zig 0.15.2+
- uv (recommended) or pip

## Documentation

See `docs/` for detailed documentation:
- [Architecture](docs/ARCHITECTURE.md)
- [Compilation Flow](docs/COMPILATION_FLOW.md)
- [Monorepo Structure](docs/MONOREPO_STRUCTURE.md)

## Status

**Phase 0: Proof of Concept** ✅

Validates core functionality. Production-ready compiler in development.

## License

[Add license]

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (coming soon)
