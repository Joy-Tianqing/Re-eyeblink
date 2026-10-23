import XCTest
import EyeblinkCore
@testable import EyeblinkApp

final class CameraObservationDeliveryTests: XCTestCase {
    @MainActor private final class Receiver {
        var values: [CameraObservation] = []
    }

    @MainActor private final class MeasurementReceiver {
        var engine: EyeblinkEngine
        let id: UUID
        let token: UUID
        var received = 0
        init() {
            var settings = AppSettings()
            settings.trainingEnabled = false; settings.measurementEnabled = false
            settings.exerciseEnabled = false; settings.breakEnabled = false
            var engine = EyeblinkEngine(settings: settings)
            id = engine.startMeasurement(at: 15)!
            token = engine.state.cameraToken!
            self.engine = engine
        }
        func receive(_ observation: CameraObservation) {
            received += 1
            if observation.isPriming { engine.cameraDidStart(token: token, at: observation.uptime) }
            else if observation.measurementFinished { engine.cameraMeasurementFinished(token: token, at: observation.uptime) }
            else {
                engine.sample(cameraToken: token, token: id, at: observation.uptime, faceValid: true, blinkDurations: observation.blinkDurations)
                if received == 2 { engine.advance(to: 195.1) }
            }
        }
    }

    @MainActor func testFinalFrameThenCompletionStayOrderedAcrossMainTicker() async throws {
        let receiver = MeasurementReceiver()
        let completed = expectation(description: "Ordered frame and completion delivered")
        let token = receiver.token
        let queue = DispatchQueue(label: "eyeblink.test.measurement-completion")
        queue.async {
            let values = [
                CameraObservation(generation: token, uptime: 15, faceCount: 0, eyeDetectionValid: false, blinkDurations: [], framesPerSecond: 0, error: nil, isPriming: true),
                CameraObservation(generation: token, uptime: 194.999, faceCount: 1, eyeDetectionValid: true, blinkDurations: [0.1875], framesPerSecond: 32, error: nil),
                CameraObservation(generation: token, uptime: 195.2, faceCount: 0, eyeDetectionValid: false, blinkDurations: [], framesPerSecond: 32, error: nil, measurementFinished: true),
                CameraObservation(generation: token, uptime: 195.3, faceCount: 1, eyeDetectionValid: true, blinkDurations: [0.5,0.5], framesPerSecond: 32, error: nil),
            ]
            for observation in values {
                CameraObservationDelivery.send(observation) { value in
                    receiver.receive(value)
                    if receiver.received == values.count { completed.fulfill() }
                }
            }
        }
        await fulfillment(of: [completed], timeout: 3)
        let effects = receiver.engine.takeEffects()
        XCTAssertEqual(effects.count, 1)
        guard case .measurementCompleted(let record) = effects.first else { return XCTFail("Expected ordered completion") }
        XCTAssertEqual(record.id, receiver.id)
        XCTAssertEqual(record.blinkDurations, [0.1875])
        XCTAssertNil(receiver.engine.state.measurement)
    }

    @MainActor func testPrimingAndFramesKeepCaptureSubmissionOrder() async {
        let receiver = Receiver()
        let completed = expectation(description: "All ordered camera metadata delivered")
        let generation = UUID()
        let queue = DispatchQueue(label: "eyeblink.test.capture-order")
        queue.async {
            for index in 0..<33 {
                let observation = CameraObservation(generation: generation, uptime: Double(index), faceCount: index == 0 ? 0 : 1,
                    eyeDetectionValid: index != 0, blinkDurations: [], framesPerSecond: 32, error: nil, isPriming: index == 0, detectionFailure: index == 32 ? .noFace : nil)
                CameraObservationDelivery.send(observation) { value in
                    receiver.values.append(value)
                    if receiver.values.count == 33 { completed.fulfill() }
                }
            }
        }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(receiver.values.map(\.uptime), (0..<33).map(Double.init))
        XCTAssertEqual(receiver.values.map(\.isPriming), [true] + Array(repeating: false, count: 32))
        XCTAssertEqual(receiver.values.map(\.detectionFailure), Array<CameraDetectionFailure?>(repeating: nil, count: 32) + [.noFace])
        XCTAssertTrue(receiver.values.allSatisfy { $0.generation == generation })
    }
}
