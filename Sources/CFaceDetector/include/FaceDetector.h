#ifndef EYEBLINK_FACE_DETECTOR_H
#define EYEBLINK_FACE_DETECTOR_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct { int32_t x, y, width, height; } EyeFaceRect;
typedef struct {
    int32_t confidence; /* original short(score * score * 100) */
    EyeFaceRect rect; /* full-frame pixel coordinates, original quarter image * 4 */
    int32_t landmarks[10];
} EyeFaceDetection;
typedef struct {
    EyeFaceRect rect;
    float leftEyeX, leftEyeY, rightEyeX, rightEyeY;
    int32_t eyeWidth;
    int32_t candidateIndex;
} EyeFaceSelection;

/* Loads the independently extracted 24-layer original weights. One immutable model
   per process; calls serialize upstream global init/filter state. Returns 1 on success. */
int eyeface_load_model(const char *model_path, char *error, size_t error_capacity);
/* Original facedetect_cnn on a caller-provided, already quarter-sized BGR image.
   Outputs full-sized coordinates (*4). Returns candidate count, or -1 on failure. */
int eyeface_detect_bgr(const uint8_t *image, int width, int height, int stride,
                      EyeFaceDetection *output, int capacity);
/* BGRA input -> BGR -> resize .25/.25 INTER_AREA, matching original resize policy. */
int eyeface_detect_bgra(const uint8_t *image, int width, int height, int stride,
                       EyeFaceDetection *output, int capacity);
/* Original initial largest-width/score>=90 selection or nearest-to-previous-center
   with score>=40. Both require full-frame width>=100; initial ties keep first. */
int eyeface_select(const EyeFaceDetection *candidates, int count, int frame_width,
                   int frame_height, const EyeFaceRect *previous, EyeFaceSelection *output);
#ifdef __cplusplus
}
#endif
#endif
