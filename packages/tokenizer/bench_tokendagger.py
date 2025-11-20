import time
import tokendagger
import base64

TEXT = """The cat sat on the mat. The dog ran in the park. The bird flew in the sky. The fish swam in the sea. The snake slithered on the ground. The rabbit hopped in the field. The fox ran through the forest. The bear climbed the tree. The wolf howled at the moon. The deer grazed in the meadow."""

# Load tiktoken vocabulary
import tiktoken as real_tiktoken
real_enc = real_tiktoken.get_encoding("cl100k_base")

# Get mergeable_ranks from tiktoken
mergeable_ranks = real_enc._mergeable_ranks

# Create tokendagger encoder with same data
enc = tokendagger.Encoding(
    name="cl100k_base",
    pat_str=real_enc._pat_str,
    mergeable_ranks=mergeable_ranks,
    special_tokens=real_enc._special_tokens
)

# Warmup
for _ in range(100):
    enc.encode(TEXT)

# Benchmark
iterations = 60000
start = time.time()
for _ in range(iterations):
    tokens = enc.encode(TEXT)
elapsed = time.time() - start

print(f"{int(elapsed * 1000)}ms")
