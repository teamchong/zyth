# Critical Correctness Gaps

**Your observation is correct:** We cannot guarantee 100% correctness with current testing.

## Current Status

### ❌ Training Correctness: CANNOT VERIFY
**Problem:** PyAOT training (`bench_train.zig`) doesn't save the trained model.

**What we can't verify:**
- Are the learned merges identical to HuggingFace/SentencePiece?
- Does the trained tokenizer produce same tokens for test texts?
- Is the vocabulary identical?

**What's needed:**
1. Save trained vocab to JSON file
2. Save merge rules in order
3. Load and encode test set
4. Compare token-by-token with HuggingFace reference

**Files to modify:**
- `src/bench_train.zig` - add model saving
- `src/tokenizer.zig` - add `save()` method

### ⚠️ Encoding Correctness: INCOMPLETE
**Problem:** `test_correctness.py` only tests ONE hardcoded text.

**What we're NOT testing:**
- All 583 benchmark texts
- Unicode edge cases (emoji, Chinese, etc.)
- Empty strings, very long strings
- Special characters
- Different text lengths

**What's needed:**
1. Make PyAOT encoder callable from Python
2. Test all 583 benchmark texts
3. Test comprehensive edge cases
4. Report FIRST mismatch with context

**Current:** ✅ Tests 1 text, ❌ Not comprehensive

## Recommendations

### Priority 1: Fix Training Verification
```zig
// In src/bench_train.zig, after training:
try tokenizer.saveToFile("pyaot_trained.json");
```

Then compare:
```python
import json
pyaot_vocab = json.load(open('pyaot_trained.json'))['vocab']
hf_vocab = hf_tokenizer.get_vocab()
assert pyaot_vocab == hf_vocab, "Vocab mismatch!"
```

### Priority 2: Comprehensive Encoding Tests
Test encoding on:
- ✅ 1 text (current)
- ❌ 583 benchmark texts
- ❌ 12 edge cases
- ❌ Adversarial cases (pathological BPE inputs)

### Priority 3: Add to Makefile
```make
test-correctness-full:
    @python3 test_training_correctness.py
    @python3 test_encoding_correctness.py
```

## Bottom Line

**You're absolutely right:**

> "if we cannot do this benchmark is meaningless"

We need 100% correctness verification BEFORE claiming performance wins.

**Action:** Should we pause optimizations and fix correctness testing first?
