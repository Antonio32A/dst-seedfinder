// Computes the C/C++-side constants of the default forest worldgen on the host toolchain (glibc libm) and prints them
// as JSON (the sidecar out/constants_c.json):
// - kk_positions: the initial KK positions. WorldGen_InitializeNodePoints builds a Boost 1.52 rectangle_topology over
//   a fresh minstd_rand (default seed 1) on every call, so vertex v gets random_point() number v; AddNewPositions
//   continues the same stream for the island vertices. Width and height 425 (SetWorldSize(425, 425)).
// - blur_kernel: GenerateBlendedMap's Gaussian kernel for kernelSize 15, sigma 3.0f (expf, sqrtf, float).
// expf and sqrtf run at run time (volatile arguments), as in the game, not folded by the compiler.
// build: g++ -O0 -std=c++17 -ffp-contract=off -isystem build/deps/boost_1_52_0 gen_constants.cpp -o gen_constants
#include <boost/graph/topology.hpp>
#include <boost/random/linear_congruential.hpp>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

static const int kPositions = 512;
static const double kWorldSize = 425.0;
static const int kKernelSize = 15;
static volatile float kSigma = 3.0f;
static volatile int kSizeVolatile = 15;

static uint64_t bits64(double x) {
    uint64_t b;
    std::memcpy(&b, &x, sizeof b);
    return b;
}

static uint32_t bits32(float x) {
    uint32_t b;
    std::memcpy(&b, &x, sizeof b);
    return b;
}

static std::vector<float> gaussian_kernel(float sigma, int size) {
    float s2 = sigma * (sigma + sigma);
    float norm = sqrtf(s2 * 3.1415927f);
    std::vector<float> kernel(size);
    float x = -(float)(size >> 1);
    for (int i = 0; i < size; ++i) {
        kernel[i] = expf(-(x * x) / s2) * (1.0f / norm);
        x = x + 1.0f;
    }
    return kernel;
}

int main() {
    boost::minstd_rand engine;
    boost::rectangle_topology<boost::minstd_rand> topology(engine, 0.0, 0.0, kWorldSize, kWorldSize);
    std::printf("{\"world_size\":%.1f,\"kk_positions\":[", kWorldSize);
    for (int v = 0; v < kPositions; ++v) {
        boost::rectangle_topology<boost::minstd_rand>::point_type p = topology.random_point();
        std::printf("%s[\"%016llx\",\"%016llx\"]", v ? "," : "", (unsigned long long)bits64(p[0]),
                    (unsigned long long)bits64(p[1]));
    }
    std::vector<float> kernel = gaussian_kernel(kSigma, kSizeVolatile);
    std::printf("],\"blur_kernel\":{\"size\":%d,\"sigma\":\"%08x\",\"weights\":[", kKernelSize, bits32(kSigma));
    for (int i = 0; i < kKernelSize; ++i) std::printf("%s\"%08x\"", i ? "," : "", bits32(kernel[i]));
    std::printf("]}}\n");
    return 0;
}
