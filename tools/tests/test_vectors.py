"""Checks the reference implementations behind the GDScript test vectors."""
import random
import shutil
import subprocess
from pathlib import Path

import pytest

import gen_vectors as gv

C_SOURCE = Path(gv.__file__).resolve().parent / "reference" / "xoshiro128ss.c"


def test_vector_files_are_current():
    assert gv.main(["--check"]) == 0


def test_split_mul32_matches_exact_product():
    pick = random.Random(7)
    pairs = [(gv.MASK32, gv.MASK32), (0, gv.MASK32), (0xFFFF, 0xFFFF0000)]
    pairs += [(pick.getrandbits(32), pick.getrandbits(32)) for _ in range(20000)]
    for a, b in pairs:
        assert gv.mul32_split(a, b) == (a * b) & gv.MASK32
        # the largest intermediate in the GDScript version stays far below 2^63
        assert a * (b & 0xFFFF) < 2**48 and a * (b >> 16) < 2**48


def test_range_int_stays_in_bounds_and_covers_span():
    rng = gv.Rng(99)
    seen = {rng.range_int(-5, 5) for _ in range(2000)}
    assert seen == set(range(-5, 6))


def test_chance_bp_rate_is_close():
    rng = gv.Rng(5)
    hits = sum(rng.chance_bp(2500) for _ in range(40000))
    assert 9500 < hits < 10500


@pytest.mark.skipif(shutil.which("cc") is None, reason="no C compiler")
def test_python_rng_matches_c_reference(tmp_path):
    exe = tmp_path / "xoshiro128ss"
    subprocess.run(["cc", "-O2", "-std=c99", "-o", str(exe), str(C_SOURCE)], check=True)
    for seed in gv.RNG_SEEDS:
        out = subprocess.run([str(exe), str(seed), "64"], check=True, capture_output=True, text=True).stdout
        rng = gv.Rng(seed)
        assert [int(line) for line in out.split()] == [rng.next_u32() for _ in range(64)], f"seed {seed}"
