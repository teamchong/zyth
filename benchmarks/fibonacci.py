def fibonacci(n: int) -> int:
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)

# Benchmark with fibonacci(35) - computationally intensive
result = fibonacci(35)
print(result)
