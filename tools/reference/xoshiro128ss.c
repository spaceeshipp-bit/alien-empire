/*
 * Independent C reference for sim/core/sim_rng.gd: xoshiro128** (the public
 * domain generator by David Blackman and Sebastiano Vigna), seeded through
 * splitmix32 exactly as the sim seeds it. Native uint32_t arithmetic wraps on
 * its own, so this checks the overflow-free GDScript and Python versions.
 *
 * Build and run (tools/tests/test_vectors.py does this when a C compiler exists):
 *   cc -O2 -o xoshiro128ss tools/reference/xoshiro128ss.c
 *   ./xoshiro128ss <seed> <count>
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static uint32_t s[4];
static uint32_t sm;

static uint32_t splitmix32(void) {
    uint32_t z = (sm += 0x9E3779B9u);
    z = (z ^ (z >> 16)) * 0x85EBCA6Bu;
    z = (z ^ (z >> 13)) * 0xC2B2AE35u;
    return z ^ (z >> 16);
}

static inline uint32_t rotl(const uint32_t x, int k) {
    return (x << k) | (x >> (32 - k));
}

static void seed(uint64_t value) {
    uint32_t lo = (uint32_t)value;
    uint32_t hi = (uint32_t)(value >> 32);
    sm = lo ^ (hi * 0x85EBCA6Bu);
    for (int i = 0; i < 4; i++) {
        s[i] = splitmix32();
    }
    if ((s[0] | s[1] | s[2] | s[3]) == 0) {
        s[0] = 1;
    }
}

static uint32_t next(void) {
    const uint32_t result = rotl(s[1] * 5, 7) * 9;
    const uint32_t t = s[1] << 9;
    s[2] ^= s[0];
    s[3] ^= s[1];
    s[1] ^= s[2];
    s[0] ^= s[3];
    s[2] ^= t;
    s[3] = rotl(s[3], 11);
    return result;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <seed> <count>\n", argv[0]);
        return 2;
    }
    seed(strtoull(argv[1], NULL, 10));
    int count = atoi(argv[2]);
    for (int i = 0; i < count; i++) {
        printf("%u\n", (unsigned)next());
    }
    return 0;
}
