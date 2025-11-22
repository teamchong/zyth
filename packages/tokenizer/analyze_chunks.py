#!/usr/bin/env python3
"""Analyze chunk sizes from cl100k_base splitter"""

import subprocess
import sys

# Sample text
text = open("taylorswift.txt", "rb").read()
print(f"Text size: {len(text)} bytes")

# Run our splitter (need to expose it)
# For now, let's estimate based on pattern

import re
pattern = r"'s|'t|'re|'ve|'m|'ll|'d| ?[a-zA-Z]+| ?[0-9]+| ?[^\sa-zA-Z0-9]+|\s+(?!\S)|\s+"

chunks = re.findall(pattern, text.decode('utf-8', errors='ignore'))
print(f"Number of chunks: {len(chunks)}")
print(f"Average chunk size: {sum(len(c.encode('utf-8')) for c in chunks) / len(chunks):.1f} bytes")

# Histogram
sizes = [len(c.encode('utf-8')) for c in chunks]
from collections import Counter
hist = Counter(sizes)
print("\nChunk size histogram (top 10):")
for size, count in sorted(hist.items(), key=lambda x: -x[1])[:10]:
    print(f"  {size:3d} bytes: {count:5d} chunks ({100*count/len(chunks):.1f}%)")

print(f"\nMax chunk size: {max(sizes)} bytes")
print(f"Chunks < 10 bytes: {sum(1 for s in sizes if s < 10)} ({100*sum(1 for s in sizes if s < 10)/len(sizes):.1f}%)")
print(f"Chunks < 20 bytes: {sum(1 for s in sizes if s < 20)} ({100*sum(1 for s in sizes if s < 20)/len(sizes):.1f}%)")
