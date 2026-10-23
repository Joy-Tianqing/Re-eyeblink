#include "CEyeFlow.h"

#include <opencv2/core.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/video/tracking.hpp>

#include <algorithm>
#include <cmath>
#include <limits>
#include <new>
#include <utility>
#include <vector>

struct EFContext {
    cv::Mat previous_gray;
    bool previous_face = false;
    EFEye previous_left{};
    EFEye previous_right{};
    float previous_normalizer = 1;
};

namespace {
bool valid_eye(const EFEye &eye) {
    constexpr double coordinate_limit = std::numeric_limits<int>::max() / 4.0;
    return std::isfinite(eye.center_x) && std::isfinite(eye.center_y)
        && std::isfinite(eye.width) && eye.width >= 0
        && std::abs(eye.center_x) < coordinate_limit
        && std::abs(eye.center_y) < coordinate_limit && eye.width < coordinate_limit;
}

EFStats flow_statistics(const cv::Mat &flow, int sample_radius, float normalizer) {
    EFStats result{};
    const double circle_radius = static_cast<float>(sample_radius) / 2.0f;
    // Match MAXSS's second-source NaN behavior. fmax/std::max would lose NaN.
    const float denominator = normalizer < 1.0f ? 1.0f : normalizer;
    double sum = 0;
    std::vector<float> samples;
    // The original walks columns before rows. Preserve accumulation order.
    for (int dx = -sample_radius; dx <= sample_radius; ++dx) {
        for (int dy = -sample_radius; dy <= sample_radius; ++dy) {
            if (std::sqrt(static_cast<double>(dx) * dx + static_cast<double>(dy) * dy) >= circle_radius) { continue; }
            const cv::Point2f movement = flow.at<cv::Point2f>(sample_radius + dy, sample_radius + dx);
            if (!(movement.x * movement.x + movement.y * movement.y < 225.0f)) { continue; }
            const float value = movement.y / denominator;
            sum += value;
            samples.push_back(value);
            ++result.sample_count;
        }
    }
    if (result.sample_count > 0) {
        result.mean_y = sum / result.sample_count;
        // The shipped function sums squared deviations in a second pass. Its
        // small-variance branch returns variance itself, not its square root.
        // E[v*v]-E[v]*E[v] both loses tiny values and changes that branch.
        double squared_deviations = 0;
        for (float value : samples) {
            const double deviation = static_cast<double>(value) - result.mean_y;
            squared_deviations += deviation * deviation;
        }
        const double variance = squared_deviations / result.sample_count;
        result.stddev_y = variance > 1e-8 ? std::sqrt(variance) : variance;
    }
    return result;
}

cv::Mat calculate_flow(const cv::Mat &previous, const cv::Mat &current) {
    cv::Mat flow;
    cv::calcOpticalFlowFarneback(previous, current, flow,
                                0.5, 3, 15, 3, 5, 1.2, 0);
    return flow;
}

cv::Rect eye_region(cv::Size image, const EFEye &eye) {
    const int half = static_cast<int>(eye.width * 0.5);
    const int x = std::max(static_cast<int>(eye.center_x) - half, 1);
    const int y = std::max(static_cast<int>(eye.center_y) - half, 1);
    const int side = std::max(std::min({static_cast<int>(eye.width), image.width - 2 - x, image.height - 2 - y}), 0);
    return {x, y, side, side};
}

EFStats sample_flow(const cv::Mat &previous, const cv::Mat &current,
                    const EFEye &eye, float normalizer) {
    const cv::Rect roi = eye_region(previous.size(), eye);
    const int side = roi.width;
    if (side < 6) { return {}; }

    // The original takes both crops at the PREVIOUS eye location. Current
    // landmarks are saved only for the following frame; do not re-center here.
    const cv::Mat flow = calculate_flow(previous(roi), current(roi));
    const int sample_radius = static_cast<int>(side * 0.5);
    return flow_statistics(flow, sample_radius, normalizer);
}
}

extern "C" EFContext *ef_create(void) {
    try { return new EFContext(); } catch (...) { return nullptr; }
}

extern "C" void ef_destroy(EFContext *context) { delete context; }

extern "C" void ef_reset(EFContext *context) {
    if (!context) { return; }
    context->previous_gray.release();
    context->previous_face = false;
    context->previous_left = {};
    context->previous_right = {};
    context->previous_normalizer = 1;
}

extern "C" int ef_prepare_gray(const uint8_t *bgra, int width, int height,
                                size_t stride, int apply_blur,
                                uint8_t *output, size_t output_stride) {
    if (!bgra || !output || width <= 0 || height <= 0
        || static_cast<size_t>(width) > std::numeric_limits<size_t>::max() / 4
        || stride < static_cast<size_t>(width) * 4
        || output_stride < static_cast<size_t>(width)
        || (apply_blur != 0 && apply_blur != 1)) { return EF_INVALID_INPUT; }
    try {
        cv::Mat input(height, width, CV_8UC4, const_cast<uint8_t *>(bgra), stride);
        cv::Mat gray(height, width, CV_8UC1, output, output_stride);
        cv::cvtColor(input, gray, cv::COLOR_BGRA2GRAY);
        if (apply_blur) { cv::blur(gray, gray, cv::Size(3, 3), cv::Point(-1, -1), 4); }
        return EF_OK;
    } catch (...) { return EF_PROCESSING_ERROR; }
}

extern "C" int ef_process(EFContext *context, const uint8_t *bgra,
                           int width, int height, size_t stride,
                           EFEye left, EFEye right, double normalizer,
                           EFResult *result) {
    return ef_process_with_face(context, bgra, width, height, stride, 1, left, right, normalizer, result);
}

extern "C" int ef_process_with_face(EFContext *context, const uint8_t *bgra,
                           int width, int height, size_t stride, int face_present,
                           EFEye left, EFEye right, double normalizer,
                           EFResult *result) {
    if (result) { *result = {}; }
    if (!context || !result || !bgra || width <= 0 || height <= 0
        || static_cast<size_t>(width) > std::numeric_limits<size_t>::max() / 4
        || stride < static_cast<size_t>(width) * 4
        || (face_present != 0 && face_present != 1)
        || (face_present && (!valid_eye(left) || !valid_eye(right)))) {
        ef_reset(context);
        return EF_INVALID_INPUT;
    }
    try {
        cv::Mat input(height, width, CV_8UC4, const_cast<uint8_t *>(bgra), stride);
        cv::Mat gray;
        cv::cvtColor(input, gray, cv::COLOR_BGRA2GRAY);
        const bool warmup = !context->previous_face || context->previous_gray.empty()
            || context->previous_gray.cols != width || context->previous_gray.rows != height;
        if (!warmup) {
            // The original blurs PREVIOUS gray only, before comparing it with
            // the unblurred current gray. This asymmetry is intentional here.
            cv::blur(context->previous_gray, context->previous_gray, cv::Size(3, 3), cv::Point(-1, -1), 4);
            result->left = sample_flow(context->previous_gray, gray,
                                        context->previous_left, context->previous_normalizer);
            result->right = sample_flow(context->previous_gray, gray,
                                         context->previous_right, context->previous_normalizer);
        }
        // A fresh original Model has no previous face. It skips that first
        // flow, then swaps the unblurred current gray into previous. Its blurred
        // pre-read image is discarded by this gate; do not blur the warmup gray.
        context->previous_gray = std::move(gray);
        context->previous_face = face_present != 0;
        if (face_present) {
            context->previous_left = left;
            context->previous_right = right;
            context->previous_normalizer = static_cast<float>(normalizer);
        }
        return warmup ? EF_WARMUP : EF_OK;
    } catch (const cv::Exception &) {
        ef_reset(context);
        return EF_PROCESSING_ERROR;
    } catch (...) {
        ef_reset(context);
        return EF_PROCESSING_ERROR;
    }
}
