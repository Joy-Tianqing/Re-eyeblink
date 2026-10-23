#ifndef CEYEFLOW_H
#define CEYEFLOW_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct EFContext EFContext;
typedef struct EFFrameNormalizer EFFrameNormalizer;

typedef struct EFClockStamp {
    int64_t ticks;
    double frequency;
} EFClockStamp;

/* Native pinned OpenCV monotonic integer tick source and frequency. */
EFClockStamp ef_clock_stamp(void);

typedef struct EFNormalizedFrame {
    const uint8_t *pixels;
    int width, height;
    size_t stride;
} EFNormalizedFrame;

typedef struct EFEye {
    double center_x;
    double center_y;
    /* 2 * round(hypot(eye landmark difference)); not the normalizer. */
    double width;
} EFEye;

typedef struct EFStats {
    double mean_y;
    /* Original compatibility: variance <= 1e-8 is returned without sqrt. */
    double stddev_y;
    int sample_count;
} EFStats;

typedef struct EFResult {
    EFStats left;
    EFStats right;
} EFResult;

enum EFStatus {
    EF_WARMUP = 0,
    EF_OK = 1,
    EF_INVALID_INPUT = -1,
    EF_INVALID_ROI = -2,
    EF_PROCESSING_ERROR = -3
};

/* Use each context from one serial queue. Images remain local to the context. */
EFContext *ef_create(void);
void ef_destroy(EFContext *context);
void ef_reset(EFContext *context);

/* Camera-open width/640 Float coefficient persists until reset, as shipped.
 * INTER_LINEAR is applied to BGR, then exposed as BGRA. Output borrows input
 * when the coefficient is exactly one, otherwise the normalizer owns it.
 * Consume synchronously before the next call/reset/destruction. */
EFFrameNormalizer *ef_normalizer_create(void);
void ef_normalizer_destroy(EFFrameNormalizer *normalizer);
void ef_normalizer_reset(EFFrameNormalizer *normalizer);
int ef_normalize_bgra(EFFrameNormalizer *normalizer, const uint8_t *bgra,
                       int width, int height, size_t stride, EFNormalizedFrame *output);

/* BGRA -> OpenCV gray, optionally with the original 3x3 blur.
 * Source and output buffers must not overlap. Returns EF_OK or a negative status. */
int ef_prepare_gray(const uint8_t *bgra, int width, int height, size_t stride,
                    int apply_blur, uint8_t *output, size_t output_stride);

/* First valid frame (or resolution change) returns EF_WARMUP. */
int ef_process(EFContext *context, const uint8_t *bgra,
               int width, int height, size_t stride,
               EFEye left, EFEye right, double normalizer, EFResult *result);

/* Complete frame gate: cache every image, including no-face frames. Flow uses
 * the PREVIOUS face/eyes. A first face after a gap returns EF_WARMUP. Current
 * eyes/normalizer are ignored when face_present is 0; only 0 or 1 is accepted. */
int ef_process_with_face(EFContext *context, const uint8_t *bgra,
                         int width, int height, size_t stride, int face_present,
                         EFEye left, EFEye right, double normalizer, EFResult *result);

#ifdef __cplusplus
}
#endif

#endif
