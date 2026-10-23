#include "CEyeFlow.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>
#include <vector>

namespace {
int checks = 0;
void require(bool value, const char *description) {
    ++checks;
    if (!value) { std::fprintf(stderr, "FAIL: %s\n", description); std::exit(1); }
}
std::vector<uint8_t> frame(int width, int height, int shift_y = 0) {
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        const int source_y = (y - shift_y + height) % height;
        for (int x = 0; x < width; ++x) {
            const uint8_t value = static_cast<uint8_t>((x * 37 + source_y * 29 + x * source_y * 7) % 256);
            const size_t offset = (static_cast<size_t>(y) * width + x) * 4;
            pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = value;
            pixels[offset + 3] = 255;
        }
    }
    return pixels;
}
}

int main() {
    const uint8_t blue[4]{255, 0, 0, 255};
    uint8_t gray = 0;
    require(ef_prepare_gray(blue, 1, 1, 4, 0, &gray, 1) == EF_OK && gray == 29, "OpenCV fixed-point blue-to-gray conversion");
    require(ef_prepare_gray(blue, 1, 1, 4, 1, &gray, 1) == EF_OK && gray == 29, "3x3 BORDER_DEFAULT blur handles a one-pixel image");
    require(ef_prepare_gray(blue, 1, 1, 4, 2, &gray, 1) == EF_INVALID_INPUT, "unsupported blur flag is rejected");
    require(ef_prepare_gray(blue, 1, 1, 4, 0, &gray, 0) == EF_INVALID_INPUT, "undersized grayscale stride is rejected");
    EFContext *context = ef_create();
    require(context != nullptr, "context allocation");
    auto first = frame(128, 80);
    auto shifted = frame(128, 80, 1);
    std::vector<uint8_t> flat(first.size(), 100);
    const EFEye left{40, 40, 32}, right{90, 40, 32};
    EFResult result{};
    auto process = [&](const std::vector<uint8_t> &pixels, EFEye a = EFEye{40, 40, 32}, EFEye b = EFEye{90, 40, 32}, double normalizer = 50) {
        return ef_process(context, pixels.data(), 128, 80, 128 * 4, a, b, normalizer, &result);
    };
    require(process(flat) == EF_WARMUP, "first valid frame warms up");
    require(process(flat) == EF_OK, "second identical uniform frame succeeds");
    require(result.left.sample_count > 0 && result.right.sample_count > 0, "both circular eye regions have samples");
    require(std::abs(result.left.mean_y) < 1e-6 && std::abs(result.right.mean_y) < 1e-6, "stationary uniform frame has zero vertical movement despite asymmetric blur");
    require(result.left.stddev_y < 1e-6 && result.right.stddev_y < 1e-6, "stationary uniform frame has zero flow deviation");

    ef_reset(context);
    require(process(first) == EF_WARMUP, "reset discards previous frame");
    require(process(shifted) == EF_OK, "translated frame succeeds");
    std::printf("Translation: left %.8f ± %.8f; right %.8f ± %.8f\n", result.left.mean_y, result.left.stddev_y, result.right.mean_y, result.right.stddev_y);
    require(result.left.mean_y > 0.005 && result.left.mean_y < 0.035, "left eye detects a downward one-pixel translation normalized by 50");
    require(result.right.mean_y > 0.005 && result.right.mean_y < 0.035, "right eye detects a downward one-pixel translation normalized by 50");

    ef_reset(context);
    require(process(first) == EF_WARMUP, "previous ROI test warms up");
    require(process(shifted, EFEye{10000, 10000, 32}, EFEye{10000, 10000, 32}) == EF_OK, "current landmarks do not move the previous-frame crop");
    require(result.left.sample_count > 0 && result.right.sample_count > 0, "previous landmarks select the same valid crop in both images");
    require(process(shifted) == EF_OK && result.left.sample_count == 0 && result.right.sample_count == 0, "offscreen landmarks affect the following frame, with zero-sample results");

    ef_reset(context);
    require(process(first, left, right, std::numeric_limits<double>::quiet_NaN()) == EF_WARMUP, "NaN normalizer is cached without replacement");
    require(process(shifted) == EF_OK && std::isnan(result.left.mean_y) && std::isnan(result.left.stddev_y), "previous normalizer NaN propagates through mean and deviation");

    ef_reset(context);
    const EFEye tiny{40, 40, 4};
    require(process(first, tiny, tiny) == EF_WARMUP, "small ROI warms up");
    require(process(first) == EF_OK && result.left.sample_count == 0 && result.left.mean_y == 0 && result.left.stddev_y == 0, "side below six preserves original zero result");

    require(ef_process(context, nullptr, 128, 80, 512, left, right, 50, &result) == EF_INVALID_INPUT, "null image is rejected");
    require(process(first) == EF_WARMUP, "invalid input clears old frames");
    require(ef_process(context, first.data(), 128, 80, 1, left, right, 50, &result) == EF_INVALID_INPUT, "undersized stride is rejected");
    auto resized = frame(96, 64);
    require(ef_process(context, resized.data(), 96, 64, 96 * 4, left, right, 50, &result) == EF_WARMUP, "new image dimensions warm up safely");
    require(process(first) == EF_WARMUP, "resolution change discards incompatible previous image");

    ef_reset(context);
    EFContext *reference = ef_create();
    require(reference != nullptr, "dropout reference context allocation");
    EFResult expected{};
    require(ef_process(reference, first.data(), 128, 80, 512, left, right, 50, &expected) == EF_WARMUP
        && process(first) == EF_WARMUP, "dropout and uninterrupted contexts start from the same face");
    require(ef_process(reference, shifted.data(), 128, 80, 512, left, right, 50, &expected) == EF_OK,
            "uninterrupted reference computes the translated frame");
    require(ef_process_with_face(context, shifted.data(), 128, 80, 512, 0, {}, {}, 1, &result) == EF_OK,
            "first lost-face frame still computes with the previous face");
    require(result.left.mean_y == expected.left.mean_y && result.left.stddev_y == expected.left.stddev_y
        && result.right.mean_y == expected.right.mean_y && result.right.stddev_y == expected.right.stddev_y
        && result.left.sample_count == expected.left.sample_count && result.right.sample_count == expected.right.sample_count,
            "lost-face frame has the same previous-eye features as the uninterrupted reference");
    require(ef_process_with_face(context, flat.data(), 128, 80, 512, 0, {}, {}, 1, &result) == EF_WARMUP
        && result.left.sample_count == 0 && result.right.sample_count == 0, "consecutive no-face frame skips flow");
    require(process(first) == EF_WARMUP, "recovered face skips flow over the no-face image");
    require(process(shifted) == EF_OK && result.left.sample_count > 0, "second recovered face resumes flow");
    require(ef_process_with_face(context, first.data(), 128, 80, 512, 2, left, right, 50, &result) == EF_INVALID_INPUT,
            "invalid face flag is rejected and clears context");
    require(process(first) == EF_WARMUP, "invalid face flag clears prior-face state");
    ef_destroy(reference);
    ef_destroy(context);
    ef_reset(nullptr);
    ef_destroy(nullptr);
    std::printf("PASS: %d optical-flow contract checks\n", checks);
    return 0;
}
