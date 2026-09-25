"""Golden model + test vector generator for mac_array_4x4.

Vector file format (all decimal ints, whitespace-separated):
  NCASES
  then per case: K, A as 4 rows x K, B as K rows x 4, C as 4 rows x 4 (expected, wrapped to int32)
"""
import argparse
import random

CORNERS = [-128, -127, -1, 0, 1, 127]


def wrap32(v):
    return ((v + 2**31) % 2**32) - 2**31


def matmul(A, B, K, n=4):
    return [[wrap32(sum(A[i][k] * B[k][j] for k in range(K))) for j in range(n)] for i in range(n)]


def rand_val(rng):
    return rng.choice(CORNERS) if rng.random() < 0.4 else rng.randint(-128, 127)


def rand_case(rng, kmax):
    K = rng.randint(1, kmax)
    A = [[rand_val(rng) for _ in range(K)] for _ in range(4)]
    B = [[rand_val(rng) for _ in range(4)] for _ in range(K)]
    return K, A, B


def const_case(K, a_val, b_val):
    return K, [[a_val] * K for _ in range(4)], [[b_val] * 4 for _ in range(K)]


def directed_cases():
    cases = [
        const_case(8, 0, 0),                        # all-zero
        const_case(16, 127, 127),                   # all-max
        const_case(16, -128, -128),                 # all-min (max positive products)
        const_case(64, -128, 127),                  # F3 margin: 64 beats of most-negative product
        const_case(8, 42, 42),                      # same-value
        const_case(1, -128, -128),                  # K=1 extreme
    ]
    # identity-ish: A = [I | I ...] pattern, K=4
    ident = [[1 if i == k else 0 for k in range(4)] for i in range(4)]
    B = [[(-1) ** (k + j) * (17 * (k + 1) + j) for j in range(4)] for k in range(4)]
    cases.append((4, ident, B))
    return cases


def emit(fh, K, A, B):
    C = matmul(A, B, K)
    fh.write(f"{K}\n")
    for i in range(4):
        fh.write(" ".join(str(A[i][k]) for k in range(K)) + "\n")
    for k in range(K):
        fh.write(" ".join(str(B[k][j]) for j in range(4)) + "\n")
    for i in range(4):
        fh.write(" ".join(str(C[i][j]) for j in range(4)) + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="vectors.txt")
    p.add_argument("--cases", type=int, default=50)
    p.add_argument("--seed", type=int, default=20260813)
    p.add_argument("--kmax", type=int, default=32)
    args = p.parse_args()

    rng = random.Random(args.seed)
    directed = directed_cases()
    n_random = max(0, args.cases - len(directed))
    with open(args.out, "w") as fh:
        fh.write(f"{len(directed) + n_random}\n")
        for K, A, B in directed:
            emit(fh, K, A, B)
        for _ in range(n_random):
            K, A, B = rand_case(rng, args.kmax)
            emit(fh, K, A, B)
    print(f"wrote {len(directed) + n_random} cases to {args.out}")


if __name__ == "__main__":
    main()
