#include "CEyeFlow.h"
#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <cmath>
#include <limits>
#include <new>

struct EFFrameNormalizer {
    bool initialized = false;
    float coefficient = 1;
    cv::Mat bgr, resized_bgr, bgra;
};

extern "C" EFFrameNormalizer *ef_normalizer_create(void) {
    try { return new EFFrameNormalizer(); } catch (...) { return nullptr; }
}

extern "C" void ef_normalizer_destroy(EFFrameNormalizer *normalizer) { delete normalizer; }

extern "C" void ef_normalizer_reset(EFFrameNormalizer *normalizer) {
    if (!normalizer) return;
    normalizer->initialized = false; normalizer->coefficient = 1;
    normalizer->bgr.release(); normalizer->resized_bgr.release(); normalizer->bgra.release();
}

extern "C" int ef_normalize_bgra(EFFrameNormalizer *normalizer, const uint8_t *bgra,
                                  int width, int height, size_t stride, EFNormalizedFrame *output) {
    if (output) *output = {};
    if (!normalizer || !output || !bgra || width <= 0 || height <= 0
        || static_cast<size_t>(width) > std::numeric_limits<size_t>::max() / 4
        || stride < static_cast<size_t>(width) * 4) {
        ef_normalizer_reset(normalizer); return EF_INVALID_INPUT;
    }
    try {
        const float coefficient = normalizer->initialized ? normalizer->coefficient : static_cast<float>(width) / 640.0f;
        if (coefficient == 1.0f) {
            *output = {bgra, width, height, stride};
        } else {
            // Shipped CVTSI2SS / DIVSS / CVTTSS2SI, not a Double aspect ratio
            // calculation or rounding-to-nearest of the target height.
            const float scaled_height = static_cast<float>(height) / coefficient;
            if (!std::isfinite(scaled_height) || scaled_height < 1
                || scaled_height >= static_cast<float>(std::numeric_limits<int>::max())) {
                ef_normalizer_reset(normalizer); return EF_INVALID_INPUT;
            }
            cv::Mat input(height, width, CV_8UC4, const_cast<uint8_t *>(bgra), stride);
            cv::cvtColor(input, normalizer->bgr, cv::COLOR_BGRA2BGR);
            cv::resize(normalizer->bgr, normalizer->resized_bgr,
                       cv::Size(640, static_cast<int>(scaled_height)), 0, 0, cv::INTER_LINEAR);
            cv::cvtColor(normalizer->resized_bgr, normalizer->bgra, cv::COLOR_BGR2BGRA);
            *output = {normalizer->bgra.ptr<uint8_t>(), normalizer->bgra.cols, normalizer->bgra.rows, normalizer->bgra.step[0]};
        }
        normalizer->coefficient = coefficient; normalizer->initialized = true;
        return EF_OK;
    } catch (...) {
        ef_normalizer_reset(normalizer); return EF_PROCESSING_ERROR;
    }
}
