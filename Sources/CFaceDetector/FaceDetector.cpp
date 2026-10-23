#include "include/FaceDetector.h"
#include "vendor/facedetectcnn.h"
#include <opencv2/imgproc.hpp>
#include <CommonCrypto/CommonDigest.h>
#include <array>
#include <cmath>
#include <cstring>
#include <fstream>
#include <limits>
#include <mutex>
#include <string>
#include <vector>

// Linked by upstream model code; parameters are supplied from original Mach-O bytes.
ConvInfoStruct param_pConvInfo[24]{};
namespace {
std::mutex modelMutex;
bool loaded = false;
std::array<std::vector<signed char>, 24> weights;
std::array<std::vector<int>, 24> biases;
std::string loadedPath;
template<class T> T read(std::ifstream &stream) {
    T value{}; stream.read(reinterpret_cast<char*>(&value), sizeof(T));
    if (!stream) throw std::runtime_error("Face model is truncated"); return value;
}
void errorText(char *output, size_t capacity, const char *message) {
    if (output && capacity) { std::strncpy(output, message, capacity - 1); output[capacity - 1] = 0; }
}
int detect(const uint8_t *image, int width, int height, int stride, EyeFaceDetection *output, int capacity) {
    if (!loaded || !image || !output || capacity < 1 || width <= 0 || height <= 0 || width > 8192 || height > 8192 || stride < width * 3) return -1;
    // Five pooling stages need ceil(input/2) >= 32. The shipped CNN returns
    // zero faces below63 after its empty final branch, rather than an error.
    if (width < 63 || height < 63) return 0;
    std::array<unsigned char, 0x20000> buffer{};
    int *result = facedetect_cnn(buffer.data(), const_cast<unsigned char*>(image), width, height, stride);
    if (!result) return -1;
    const int count = std::min(std::max(*result, 0), capacity);
    for (int i = 0; i < count; ++i) {
        const short *p = reinterpret_cast<const short*>(buffer.data() + 4) + 142 * i;
        output[i].confidence = p[0]; output[i].rect = {p[1] * 4, p[2] * 4, p[3] * 4, p[4] * 4};
        for (int j = 0; j < 10; ++j) output[i].landmarks[j] = p[5 + j] * 4;
    }
    return count;
}
}
extern "C" int eyeface_load_model(const char *path, char *error, size_t capacity) {
    std::lock_guard<std::mutex> lock(modelMutex);
    try {
        if (!path) throw std::runtime_error("Missing face model path");
        if (loaded) {
            if (loadedPath != path) throw std::runtime_error("Face model is immutable after initialization");
            return 1;
        }
        std::ifstream stream(path, std::ios::binary);
        std::vector<unsigned char> serialized((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
        unsigned char digest[CC_SHA256_DIGEST_LENGTH]{};
        CC_SHA256(serialized.data(), static_cast<CC_LONG>(serialized.size()), digest);
        const unsigned char expected[CC_SHA256_DIGEST_LENGTH] = {
            0x83,0x53,0x05,0xbf,0xac,0x32,0x4d,0x22,0x10,0x25,0x80,0xf5,0x98,0xa7,0xdf,0x64,
            0x19,0x37,0x8b,0x7d,0x68,0x13,0x8c,0x08,0x5c,0x43,0x66,0x5a,0x97,0x7d,0x77,0x67
        };
        if (serialized.size() != 2327596 || std::memcmp(digest, expected, sizeof digest)) throw std::runtime_error("Face model SHA-256 does not match the recovered original");
        stream.clear(); stream.seekg(0);
        char magic[8]{}; stream.read(magic, 8);
        if (std::memcmp(magic, "EYFC24V1", 8) || read<uint32_t>(stream) != 24) throw std::runtime_error("Unsupported face model format");
        std::array<ConvInfoStruct, 24> parameters{};
        std::array<std::vector<signed char>, 24> newWeights;
        std::array<std::vector<int>, 24> newBiases;
        for (int i = 0; i < 24; ++i) {
            auto &p = parameters[i]; p.pad = read<int32_t>(stream); p.stride = read<int32_t>(stream);
            p.kernel_size = read<int32_t>(stream); p.channels = read<int32_t>(stream); p.num = read<int32_t>(stream); p.scale = read<float>(stream);
            const auto weightBytes = read<uint32_t>(stream), biasBytes = read<uint32_t>(stream);
            if (p.pad < 0 || p.pad > 1 || p.stride < 1 || p.stride > 2 || (p.kernel_size != 1 && p.kernel_size != 3) ||
                p.channels < 1 || p.channels > 256 || p.num < 1 || p.num > 256 || !std::isfinite(p.scale) || p.scale <= 0 ||
                weightBytes != uint32_t(p.kernel_size * p.kernel_size * p.channels * p.num) || biasBytes != uint32_t(p.num * 4))
                throw std::runtime_error("Invalid face convolution metadata");
            newWeights[i].resize(weightBytes); newBiases[i].resize(p.num);
            stream.read(reinterpret_cast<char*>(newWeights[i].data()), weightBytes);
            stream.read(reinterpret_cast<char*>(newBiases[i].data()), biasBytes);
            if (!stream) throw std::runtime_error("Face model is truncated");
        }
        if (stream.peek() != std::char_traits<char>::eof()) throw std::runtime_error("Unexpected trailing face model bytes");
        weights = std::move(newWeights); biases = std::move(newBiases);
        for (int i = 0; i < 24; ++i) {
            parameters[i].pWeights = weights[i].data(); parameters[i].pBias = biases[i].data(); param_pConvInfo[i] = parameters[i];
        }
        loadedPath = path; loaded = true; errorText(error, capacity, ""); return 1;
    } catch (const std::exception &e) { errorText(error, capacity, e.what()); return 0; }
}
extern "C" int eyeface_detect_bgr(const uint8_t *image, int width, int height, int stride, EyeFaceDetection *output, int capacity) {
    std::lock_guard<std::mutex> lock(modelMutex);
    try { return detect(image, width, height, stride, output, capacity); } catch (...) { return -1; }
}
extern "C" int eyeface_detect_bgra(const uint8_t *image, int width, int height, int stride, EyeFaceDetection *output, int capacity) {
    std::lock_guard<std::mutex> lock(modelMutex);
    if (!image || width <= 0 || height <= 0 || width > 8192 || height > 8192 || stride < width * 4) return -1;
    try {
        cv::Mat source(height, width, CV_8UC4, const_cast<uint8_t*>(image), stride), bgr, small;
        cv::cvtColor(source, bgr, cv::COLOR_BGRA2BGR);
        // Let OpenCV apply the original quarter-scale rounding. Raw251/255
        // can produce63/64 and remain valid CNN inputs; a raw256 floor loses faces.
        cv::resize(bgr, small, cv::Size(), .25, .25, cv::INTER_AREA);
        return detect(small.data, small.cols, small.rows, int(small.step), output, capacity);
    } catch (...) { return -1; }
}
extern "C" int eyeface_select(const EyeFaceDetection *faces, int count, int frameWidth, int frameHeight, const EyeFaceRect *previous, EyeFaceSelection *output) {
    if (!faces || count < 0 || count > 256 || !output || frameWidth < 1 || frameHeight < 1) return 0;
    int selected = -1, largest = 0;
    int64_t distance = std::numeric_limits<int64_t>::max();
    for (int i = 0; i < count; ++i) {
        const auto &face = faces[i];
        if (face.rect.width < 100 || face.confidence < (previous ? 40 : 90)) continue;
        if (previous) {
            const int64_t dx = int64_t(previous->x) + previous->width / 2 - int64_t(face.rect.x) - face.rect.width / 2;
            const int64_t dy = int64_t(previous->y) + previous->height / 2 - int64_t(face.rect.y) - face.rect.height / 2;
            const int64_t squared = dx * dx + dy * dy;
            if (squared >= distance) continue; distance = squared;
        } else { if (face.rect.width <= largest) continue; largest = face.rect.width; }
        selected = i;
    }
    if (selected < 0) return 0;
    const auto &face = faces[selected];
    output->rect = {std::max(0, face.rect.x), std::max(0, face.rect.y),
        std::min(frameWidth - face.rect.x - 3, face.rect.width), std::min(frameHeight - face.rect.y - 3, face.rect.height)};
    output->leftEyeX = face.landmarks[0]; output->leftEyeY = face.landmarks[1];
    output->rightEyeX = face.landmarks[2]; output->rightEyeY = face.landmarks[3];
    output->eyeWidth = face.rect.width / 2; output->candidateIndex = selected;
    // Reject impossible clipping instead of passing an invalid ROI to downstream C++.
    return output->rect.width > 0 && output->rect.height > 0;
}
