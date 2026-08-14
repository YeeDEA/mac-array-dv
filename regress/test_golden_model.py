"""Unit tests for regress/golden_model.py — the reference model the UVM scoreboard
and the Python cross-check in run_regress.py are both measured against.

The golden model is the only thing in this project that is *not* checked by anything
else: if it is wrong, every "PASS" downstream is meaningless. These tests pin down
its four load-bearing properties:

  1. wrap32() implements INT32 two's-complement wraparound exactly at +-2^31.
  2. matmul() computes C(4x4) = A(4xK) . B(Kx4) (hand-checked example below).
  3. directed_cases() still emits the documented corner tiles (-128*-128, K=1, K=64).
  4. Accumulation is exact — never wraps — for the in-spec bound K <= 64 at maximum
     operand magnitude, which is the 32-bit accumulator argument in docs/spec.md
     ("16 + ceil(log2 N) bits -> exact for N <= 2^15 beats").

No simulator is required; this job is the part of CI that can run without Vivado.
"""
import io
import os
import random
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from golden_model import (  # noqa: E402
    CORNERS,
    const_case,
    directed_cases,
    emit,
    matmul,
    rand_case,
    rand_val,
    wrap32,
)

# ---------------------------------------------------------------- constants
INT8_MIN, INT8_MAX = -128, 127
INT32_MIN, INT32_MAX = -(2 ** 31), 2 ** 31 - 1

# docs/spec.md: INT8 x INT8 product is in [-16256, +16384]
PROD_MAX = INT8_MIN * INT8_MIN   # -128 * -128 = +16384 (most positive product)
PROD_MIN = INT8_MIN * INT8_MAX   # -128 * +127 = -16256 (most negative product)

K_SPEC_MAX = 64                  # docs/spec.md: "tests use K <= 64"
ACC_EXACT_BEATS = 2 ** 15        # docs/spec.md: 32-bit acc exact for N <= 2^15 beats


# ---------------------------------------------------------------- helpers
def unwrapped_matmul(A, B, K):
    """Same product-sum as matmul() but with unbounded Python ints (no wrap).

    Comparing matmul() against this proves whether a wrap actually occurred.
    """
    return [[sum(A[i][k] * B[k][j] for k in range(K)) for j in range(4)] for i in range(4)]


def ref_wrap32(v):
    """Independent reimplementation of wrap32: mask to 32 bits, reinterpret as signed."""
    u = v & 0xFFFFFFFF
    return u - 2 ** 32 if u >= 2 ** 31 else u


def wrap16(v):
    """The BUG1 hook's behaviour (accumulator truncated to 16 bits)."""
    return ((v + 2 ** 15) % 2 ** 16) - 2 ** 15


def const_signature(K, A, B):
    """(K, a_val, b_val) if the case is a constant tile, else None."""
    a_vals = {v for row in A for v in row}
    b_vals = {v for row in B for v in row}
    if len(a_vals) == 1 and len(b_vals) == 1:
        return (K, a_vals.pop(), b_vals.pop())
    return None


# ================================================================ wrap32
class TestWrap32:
    """INT32 wraparound behaviour, especially the +-2^31 boundary."""

    @pytest.mark.parametrize("raw, expected", [
        (0, 0),
        (1, 1),
        (-1, -1),
        (INT32_MAX, INT32_MAX),                 # +2^31 - 1 : largest in-range value
        (INT32_MIN, INT32_MIN),                 # -2^31     : smallest in-range value
        (2 ** 31, INT32_MIN),                   # +2^31     : wraps to most negative
        (2 ** 31 + 1, INT32_MIN + 1),
        (2 ** 31 + 12345, INT32_MIN + 12345),
        (-(2 ** 31) - 1, INT32_MAX),            # one below the floor -> most positive
        (-(2 ** 31) - 12345, INT32_MAX - 12344),
        (2 ** 32, 0),                           # full period
        (2 ** 32 - 1, -1),
        (-(2 ** 32), 0),
        (3 * 2 ** 31, INT32_MIN),               # 1.5 periods
        (2 ** 40, 0),
    ])
    def test_boundary_values(self, raw, expected):
        assert wrap32(raw) == expected

    def test_identity_inside_int32_range(self):
        for v in (INT32_MIN, INT32_MIN + 1, -1, 0, 1, INT32_MAX - 1, INT32_MAX):
            assert wrap32(v) == v

    def test_step_across_the_positive_boundary(self):
        """The single-LSB step over +2^31 must jump the full 2^32 period."""
        assert wrap32(INT32_MAX) == INT32_MAX
        assert wrap32(INT32_MAX + 1) == INT32_MIN
        assert wrap32(INT32_MAX + 1) - wrap32(INT32_MAX) == -(2 ** 32) + 1

    def test_step_across_the_negative_boundary(self):
        assert wrap32(INT32_MIN) == INT32_MIN
        assert wrap32(INT32_MIN - 1) == INT32_MAX

    def test_result_always_in_int32_range(self):
        rng = random.Random(20260813)
        samples = [rng.randint(-(2 ** 48), 2 ** 48) for _ in range(500)]
        samples += [2 ** 31, -(2 ** 31), 2 ** 32, -(2 ** 32), 0, INT32_MAX, INT32_MIN]
        for v in samples:
            assert INT32_MIN <= wrap32(v) <= INT32_MAX

    def test_idempotent(self):
        rng = random.Random(7)
        for _ in range(300):
            v = rng.randint(-(2 ** 40), 2 ** 40)
            assert wrap32(wrap32(v)) == wrap32(v)

    def test_matches_independent_twos_complement_reference(self):
        rng = random.Random(99)
        edge = [0, 1, -1, 2 ** 31, -(2 ** 31), 2 ** 31 - 1, 2 ** 32, -(2 ** 32), 2 ** 31 + 1]
        for v in edge + [rng.randint(-(2 ** 40), 2 ** 40) for _ in range(300)]:
            assert wrap32(v) == ref_wrap32(v)

    def test_period_is_exactly_2_pow_32(self):
        rng = random.Random(5)
        for _ in range(100):
            v = rng.randint(-(2 ** 33), 2 ** 33)
            assert wrap32(v) == wrap32(v + 2 ** 32) == wrap32(v - 2 ** 32)


# ================================================================ matmul
# Hand-computed reference tile (K = 4), worked out by hand from
# C[i][j] = sum_k A[i][k] * B[k][j]:
#
#   row 0: 1*[1,0,-1,2] + (-2)*[3,-4,5,-6] + 3*[-7,8,0,1] + (-4)*[9,-10,11,-12]
#          = [1-6-21-36, 0+8+24+40, -1-10+0-44, 2+12+3+48] = [-62, 72, -55, 65]
#   row 1: 0*[..] + 5*[3,-4,5,-6] + (-6)*[-7,8,0,1] + 7*[9,-10,11,-12]
#          = [15+42+63, -20-48-70, 25+0+77, -30-6-84]       = [120, -138, 102, -120]
#   row 2: -8*[1,0,-1,2] + 9*[3,-4,5,-6] + 0*[..] + 1*[9,-10,11,-12]
#          = [-8+27+9, 0-36-10, 8+45+11, -16-54-12]         = [28, -46, 64, -82]
#   row 3: 2*[1,0,-1,2] + (-3)*[3,-4,5,-6] + 4*[-7,8,0,1] + (-5)*[9,-10,11,-12]
#          = [2-9-28-45, 0+12+32+50, -2-15+0-55, 4+18+4+60] = [-80, 94, -72, 86]
HAND_A = [
    [1, -2, 3, -4],
    [0, 5, -6, 7],
    [-8, 9, 0, 1],
    [2, -3, 4, -5],
]
HAND_B = [
    [1, 0, -1, 2],
    [3, -4, 5, -6],
    [-7, 8, 0, 1],
    [9, -10, 11, -12],
]
HAND_C = [
    [-62, 72, -55, 65],
    [120, -138, 102, -120],
    [28, -46, 64, -82],
    [-80, 94, -72, 86],
]


class TestMatmul:
    def test_hand_computed_4x4_example(self):
        assert matmul(HAND_A, HAND_B, 4) == HAND_C

    def test_hand_computed_example_is_self_consistent(self):
        """Guards the hand table itself against a transcription slip."""
        assert unwrapped_matmul(HAND_A, HAND_B, 4) == HAND_C

    def test_result_is_always_4x4(self):
        for K in (1, 2, 4, 7, 64):
            _, A, B = const_case(K, 3, -5)
            C = matmul(A, B, K)
            assert len(C) == 4
            assert all(len(row) == 4 for row in C)

    def test_is_not_symmetric_i_j(self):
        """A[i][k]*B[k][j] — catches a transposed-index regression."""
        A = [[1, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
        B = [[0, 5, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]]
        C = matmul(A, B, 4)
        assert C[0][1] == 5          # row 0, col 1
        assert C[1][0] == 0          # and NOT the transpose
        assert sum(sum(r) for r in C) == 5

    def test_k_argument_bounds_the_reduction(self):
        """matmul consumes only the first K columns of A / first K rows of B."""
        full = matmul(HAND_A, HAND_B, 4)
        two = matmul(HAND_A, HAND_B, 2)
        truncated = matmul([row[:2] for row in HAND_A], HAND_B[:2], 2)
        assert two == truncated
        assert two != full

    def test_identity_a_passes_b_through(self):
        ident = [[1 if i == k else 0 for k in range(4)] for i in range(4)]
        assert matmul(ident, HAND_B, 4) == HAND_B

    def test_zero_tile(self):
        K, A, B = const_case(8, 0, 0)
        assert matmul(A, B, K) == [[0] * 4 for _ in range(4)]

    def test_wrap32_is_applied_inside_matmul(self):
        """Deliberately out-of-spec magnitudes (not INT8) — the only way to make a
        4x4 tile exceed INT32 without streaming ~2^17 beats. Proves the wrap lives
        inside matmul(), mirroring the RTL's 32-bit accumulator rollover."""
        A = [[2 ** 16] for _ in range(4)]
        B = [[2 ** 15, 2 ** 16, 1, -1]]
        C = matmul(A, B, 1)
        assert C[0][0] == INT32_MIN        # 2^16 * 2^15 = +2^31 -> wraps
        assert C[0][1] == 0                # 2^16 * 2^16 = +2^32 -> wraps
        assert C[0][2] == 2 ** 16          # in range, untouched
        assert C[0][3] == -(2 ** 16)


# ================================================================ K = 1
class TestKEqualsOne:
    """K=1 degenerates to a pure outer product — the shortest legal tile."""

    def test_k1_is_the_outer_product(self):
        A = [[INT8_MIN], [-1], [0], [INT8_MAX]]
        B = [[INT8_MIN, -1, 0, INT8_MAX]]
        C = matmul(A, B, 1)
        for i in range(4):
            for j in range(4):
                assert C[i][j] == A[i][0] * B[0][j]

    def test_k1_extreme_products(self):
        A = [[INT8_MIN], [-1], [0], [INT8_MAX]]
        B = [[INT8_MIN, -1, 0, INT8_MAX]]
        C = matmul(A, B, 1)
        assert C[0][0] == 16384        # -128 * -128, largest positive product
        assert C[0][3] == -16256       # -128 * +127, largest negative product
        assert C[3][0] == -16256       # +127 * -128
        assert C[3][3] == 16129        # +127 * +127
        assert C[2] == [0, 0, 0, 0]    # zero row
        assert [row[2] for row in C] == [0, 0, 0, 0]   # zero column

    def test_k1_never_wraps(self):
        """A single INT8 product can never leave INT32."""
        for a in (INT8_MIN, -1, 0, 1, INT8_MAX):
            for b in (INT8_MIN, -1, 0, 1, INT8_MAX):
                K, A, B = const_case(1, a, b)
                C = matmul(A, B, K)
                assert C == unwrapped_matmul(A, B, K)
                assert all(v == a * b for row in C for v in row)

    def test_directed_set_contains_the_k1_extreme(self):
        sigs = [const_signature(K, A, B) for K, A, B in directed_cases()]
        assert (1, INT8_MIN, INT8_MIN) in sigs


# ================================================================ directed_cases
class TestDirectedCases:
    def test_shapes_and_int8_domain(self):
        cases = directed_cases()
        assert len(cases) == 7
        for K, A, B in cases:
            assert K >= 1
            assert len(A) == 4 and all(len(row) == K for row in A), "A must be 4 x K"
            assert len(B) == K and all(len(row) == 4 for row in B), "B must be K x 4"
            for row in list(A) + list(B):
                for v in row:
                    assert INT8_MIN <= v <= INT8_MAX, f"{v} is not a signed INT8"

    def test_documented_constant_tiles_are_all_present(self):
        """The corner tiles named in docs/spec.md and golden_model's comments."""
        sigs = {const_signature(K, A, B) for K, A, B in directed_cases()}
        sigs.discard(None)
        assert sigs == {
            (8, 0, 0),                      # all-zero
            (16, INT8_MAX, INT8_MAX),       # all-max
            (16, INT8_MIN, INT8_MIN),       # all-min -> max positive products
            (64, INT8_MIN, INT8_MAX),       # F3 margin: 64 most-negative products
            (8, 42, 42),                    # same-value
            (1, INT8_MIN, INT8_MIN),        # K=1 extreme
        }

    @pytest.mark.parametrize("sig, cell", [
        ((8, 0, 0), 0),
        ((16, INT8_MAX, INT8_MAX), 16 * 127 * 127),        # 258064
        ((16, INT8_MIN, INT8_MIN), 16 * PROD_MAX),         # 262144
        ((64, INT8_MIN, INT8_MAX), 64 * PROD_MIN),         # -1040384
        ((8, 42, 42), 8 * 42 * 42),                        # 14112
        ((1, INT8_MIN, INT8_MIN), PROD_MAX),               # 16384
    ])
    def test_constant_tile_expected_values(self, sig, cell):
        K, a_val, b_val = sig
        _, A, B = const_case(K, a_val, b_val)
        C = matmul(A, B, K)
        assert all(v == cell for row in C for v in row)
        assert C == unwrapped_matmul(A, B, K), "in-spec directed tile must not wrap"

    def test_minus128_times_minus128_extreme_is_covered(self):
        """The sign-handling extreme: -128 * -128 = +16384 (BUG4's blind spot)."""
        _, A, B = const_case(1, INT8_MIN, INT8_MIN)
        assert matmul(A, B, 1)[0][0] == 16384
        _, A16, B16 = const_case(16, INT8_MIN, INT8_MIN)
        assert matmul(A16, B16, 16)[0][0] == 16 * 16384 == 262144

    def test_identity_case_passes_b_through(self):
        """The last directed case is A = I(4x4), so C must equal B exactly."""
        non_const = [c for c in directed_cases() if const_signature(*c) is None]
        assert len(non_const) == 1
        K, A, B = non_const[0]
        assert K == 4
        assert A == [[1 if i == k else 0 for k in range(4)] for i in range(4)]
        assert matmul(A, B, K) == B
        assert B[0] == [17, -18, 19, -20]      # (-1)^(k+j) * (17*(k+1)+j)
        assert B[3] == [-68, 69, -70, 71]

    def test_k_values_stay_within_the_spec_bound(self):
        ks = [K for K, _, _ in directed_cases()]
        assert min(ks) == 1
        assert max(ks) == K_SPEC_MAX, "docs/spec.md: tests use K <= 64"
        assert K_SPEC_MAX in ks and 1 in ks

    def test_no_directed_case_wraps(self):
        for K, A, B in directed_cases():
            assert matmul(A, B, K) == unwrapped_matmul(A, B, K)


# ================================================================ accumulator width
class TestAccumulatorExactness:
    """docs/spec.md: 'Accumulating N products needs 16 + ceil(log2 N) bits ->
    32-bit acc is exact for N <= 2^15 beats. Tests bound K <= 64 -> margin >= 2^9.'
    """

    def test_int8_product_range_matches_spec(self):
        products = [a * b for a in range(INT8_MIN, INT8_MAX + 1)
                    for b in range(INT8_MIN, INT8_MAX + 1)]
        assert min(products) == PROD_MIN == -16256
        assert max(products) == PROD_MAX == 16384
        # docs/spec.md: "16 bits signed (fits s16 range -32768..32767)"
        assert -(2 ** 15) <= PROD_MIN <= PROD_MAX <= 2 ** 15 - 1

    def test_k64_max_positive_magnitude_is_exact(self):
        """64 beats of -128 * -128 = +16384 each."""
        K, A, B = const_case(K_SPEC_MAX, INT8_MIN, INT8_MIN)
        expected = K_SPEC_MAX * PROD_MAX
        assert expected == 1048576
        C = matmul(A, B, K)
        assert all(v == expected for row in C for v in row)
        assert C == unwrapped_matmul(A, B, K), "32-bit accumulator must not wrap"
        assert INT32_MIN <= expected <= INT32_MAX

    def test_k64_max_negative_magnitude_is_exact(self):
        """64 beats of -128 * +127 = -16256 each (the F3 margin case)."""
        K, A, B = const_case(K_SPEC_MAX, INT8_MIN, INT8_MAX)
        expected = K_SPEC_MAX * PROD_MIN
        assert expected == -1040384
        C = matmul(A, B, K)
        assert all(v == expected for row in C for v in row)
        assert C == unwrapped_matmul(A, B, K)
        assert INT32_MIN <= expected <= INT32_MAX

    @pytest.mark.parametrize("a_val, b_val", [
        (INT8_MIN, INT8_MIN),
        (INT8_MIN, INT8_MAX),
        (INT8_MAX, INT8_MIN),
        (INT8_MAX, INT8_MAX),
        (INT8_MIN, 1),
        (INT8_MAX, -1),
    ])
    def test_no_wrap_for_any_k_up_to_64(self, a_val, b_val):
        for K in range(1, K_SPEC_MAX + 1):
            _, A, B = const_case(K, a_val, b_val)
            C = matmul(A, B, K)
            assert C == unwrapped_matmul(A, B, K), f"wrapped at K={K}"
            assert all(v == K * a_val * b_val for row in C for v in row)

    def test_spec_bound_of_2_pow_15_beats_holds(self):
        """The exactness claim itself: N = 2^15 worst-case beats still fits INT32."""
        assert ACC_EXACT_BEATS * PROD_MAX <= INT32_MAX     # 2^15 * 16384 = 536870912
        assert ACC_EXACT_BEATS * PROD_MIN >= INT32_MIN     # 2^15 * -16256 = -532676608

    def test_spec_bound_is_conservative_and_the_real_cliff_is_2_pow_17(self):
        """spec.md derives N <= 2^15 from a 16-bit product bound; the true max product
        is 2^14, so INT32 actually survives up to 2^17 - 1 beats. The spec bound is
        therefore safe, and the first N that can wrap is 2^17."""
        assert (2 ** 17 - 1) * PROD_MAX <= INT32_MAX       # 2147467264
        assert (2 ** 17) * PROD_MAX > INT32_MAX            # 2^31 overflows by one
        assert wrap32((2 ** 17) * PROD_MAX) == INT32_MIN
        assert ACC_EXACT_BEATS < 2 ** 17, "spec bound must sit below the real cliff"

    def test_k64_headroom_is_at_least_2_pow_9_beats(self):
        assert ACC_EXACT_BEATS // K_SPEC_MAX >= 2 ** 9
        assert INT32_MAX // (K_SPEC_MAX * PROD_MAX) >= 2 ** 9

    def test_k64_max_magnitude_is_a_discriminating_case(self):
        """A 16-bit accumulator (the BUG1 hook) WOULD corrupt this tile — so the
        K=64 max-magnitude vector actually exercises the 16 guard bits."""
        exact = K_SPEC_MAX * PROD_MAX
        assert wrap16(exact) != exact
        assert wrap32(exact) == exact
        exact_neg = K_SPEC_MAX * PROD_MIN
        assert wrap16(exact_neg) != exact_neg
        assert wrap32(exact_neg) == exact_neg


# ================================================================ generators / emit
class TestGenerators:
    def test_corners_cover_the_int8_extremes(self):
        assert INT8_MIN in CORNERS
        assert INT8_MAX in CORNERS
        assert 0 in CORNERS
        assert all(INT8_MIN <= v <= INT8_MAX for v in CORNERS)

    def test_rand_val_stays_in_int8(self):
        rng = random.Random(20260813)
        for _ in range(2000):
            assert INT8_MIN <= rand_val(rng) <= INT8_MAX

    def test_rand_case_is_seed_deterministic_and_well_shaped(self):
        a = rand_case(random.Random(20260813), 32)
        b = rand_case(random.Random(20260813), 32)
        assert a == b, "same seed must reproduce the same tile (repro commands rely on it)"
        K, A, B = a
        assert 1 <= K <= 32
        assert len(A) == 4 and all(len(row) == K for row in A)
        assert len(B) == K and all(len(row) == 4 for row in B)
        assert all(INT8_MIN <= v <= INT8_MAX for row in list(A) + list(B) for v in row)

    def test_const_case_shape(self):
        K, A, B = const_case(5, -7, 9)
        assert K == 5
        assert A == [[-7] * 5 for _ in range(4)]
        assert B == [[9] * 4 for _ in range(5)]

    def test_emit_file_layout(self):
        """Format per golden_model's docstring: K, then A (4 x K), B (K x 4), C (4 x 4)."""
        K, A, B = const_case(3, 2, -3)
        fh = io.StringIO()
        emit(fh, K, A, B)
        lines = fh.getvalue().strip().split("\n")
        assert len(lines) == 1 + 4 + K + 4
        assert int(lines[0]) == K
        assert [list(map(int, lines[1 + i].split())) for i in range(4)] == A
        assert [list(map(int, lines[5 + k].split())) for k in range(K)] == B
        c_rows = [list(map(int, lines[5 + K + r].split())) for r in range(4)]
        assert c_rows == matmul(A, B, K)
        assert all(v == 3 * 2 * -3 for row in c_rows for v in row)   # -18

    def test_cli_writes_a_parsable_vector_file(self, tmp_path):
        out = tmp_path / "vectors.txt"
        res = subprocess.run(
            [sys.executable, os.path.join(HERE, "golden_model.py"),
             "--out", str(out), "--cases", "12", "--seed", "20260813", "--kmax", "16"],
            capture_output=True, text=True,
        )
        assert res.returncode == 0, res.stderr
        tok = out.read_text().split()
        pos = 0
        ncases = int(tok[pos]); pos += 1
        assert ncases == 12, "7 directed + 5 random"
        ks = []
        for _ in range(ncases):
            K = int(tok[pos]); pos += 1
            A = [[int(tok[pos + i * K + k]) for k in range(K)] for i in range(4)]
            pos += 4 * K
            B = [[int(tok[pos + k * 4 + j]) for j in range(4)] for k in range(K)]
            pos += 4 * K
            C = [[int(tok[pos + i * 4 + j]) for j in range(4)] for i in range(4)]
            pos += 16
            ks.append(K)
            assert K >= 1
            assert all(INT8_MIN <= v <= INT8_MAX for row in A + B for v in row)
            assert C == matmul(A, B, K), "emitted C must match the model"
            assert all(INT32_MIN <= v <= INT32_MAX for row in C for v in row)
        assert pos == len(tok), "no trailing or missing tokens"
        # directed cases go first and ignore --kmax (the K=64 margin tile must survive);
        # only the random tail is bounded by --kmax.
        directed_ks = [K for K, _, _ in directed_cases()]
        assert ks[:len(directed_ks)] == directed_ks
        assert K_SPEC_MAX in ks
        assert all(1 <= K <= 16 for K in ks[len(directed_ks):]), "--kmax bounds random cases"
