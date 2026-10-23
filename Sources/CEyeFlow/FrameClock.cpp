#include "CEyeFlow.h"
#include <opencv2/core.hpp>

extern "C" EFClockStamp ef_clock_stamp(void) {
    return {cv::getTickCount(), cv::getTickFrequency()};
}
