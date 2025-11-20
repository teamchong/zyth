| Command | Mean [ms] | Min [ms] | Max [ms] | Relative |
|:---|---:|---:|---:|---:|
| `./zig-out/bin/tokenizer_bench` | 824.5 ± 9.8 | 816.2 | 841.2 | 1.08 ± 0.01 |
| `python3 bench_tokendagger.py` | 764.8 ± 4.5 | 758.7 | 769.6 | 1.00 |
| `python3 bench_tiktoken.py` | 1192.8 ± 4.0 | 1189.0 | 1197.5 | 1.56 ± 0.01 |
| `python3 bench_huggingface.py` | 5288.8 ± 32.9 | 5240.2 | 5321.2 | 6.92 ± 0.06 |
| `cargo run --release --manifest-path benchmark_rust/Cargo.toml` | 9732.4 ± 59.8 | 9694.2 | 9836.1 | 12.72 ± 0.11 |
