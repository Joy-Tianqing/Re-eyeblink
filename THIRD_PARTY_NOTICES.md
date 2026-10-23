# Third-party notices

The root [LICENSE](LICENSE) covers only original Re-eyeblink material that
the maintainer has the right to license. It does not replace third-party
licenses, claim ownership of upstream work, or grant rights in external models.
Preserve applicable upstream notices when redistributing source or binaries.

## libfacedetection

- Upstream: <https://github.com/ShiqiYu/libfacedetection>
- Pinned model source: commit `77b54ba85601191b1ce61772e735b694faeaf714`.
- License: BSD 3-Clause; copyright (c) 2015–2019 Shiqi Yu.
- Vendored code and notice: [`Sources/CFaceDetector/vendor/`](Sources/CFaceDetector/vendor/), including its [LICENSE](Sources/CFaceDetector/vendor/LICENSE).
- The CNN model is materialized during setup from the pinned upstream source.
  Its identity is recorded in [`official-model-materialization.json`](evidence/static/recovered-face/official-model-materialization.json).

## OpenCV 4.4.0

- Upstream: <https://github.com/opencv/opencv/tree/4.4.0>
- License: BSD 3-Clause for this pinned version; see the [upstream license](https://github.com/opencv/opencv/blob/4.4.0/LICENSE).
- Downloaded and built locally by [`scripts/build-opencv.sh`](scripts/build-opencv.sh).
- The source archive and project patches are checksum-pinned. The build script
  copies the upstream license into the generated application's
  `Contents/Resources/Licenses/` directory.

## dlib-related implementation

- Upstream: <https://github.com/davisking/dlib>
- License: Boost Software License 1.0; retained in
  [`packaging/Licenses/dlib-LICENSE.txt`](packaging/Licenses/dlib-LICENSE.txt).
- Re-eyeblink implements the five-point predictor loading and inference in
  Swift. Retain applicable upstream notices for dlib-derived implementation.
- The dlib code license does not by itself license a particular trained model.

## External five-point model and original application

The original eyeblink application and its `data.dat` five-point model are not
distributed by this repository. Users must independently obtain the required
model and the rights needed for their use. A SHA-256 match verifies model
identity, not permission to use or redistribute it. Local build scripts copy
the provided model into an application bundle; that step does not grant
redistribution rights for the model or the resulting bundle.

The original eyeblink / Blinking Matters names and other third-party marks
belong to their respective owners. This independent reconstruction project
is not affiliated with or endorsed by those owners.
