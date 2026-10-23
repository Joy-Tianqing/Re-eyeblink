import XCTest
import EyeblinkCore
@testable import EyeblinkApp

private actor NotificationGate {
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async { if !opened { await withCheckedContinuation { waiting.append($0) } } }
    func open() { opened = true; let pending = waiting; waiting.removeAll(); pending.forEach { $0.resume() } }
}

private actor NotificationClientFixture: MeasurementNotificationClient {
    var status: NotificationAuthorization
    var requested = 0
    var posted: [MeasurementNotification] = []
    var removed: [String] = []
    var failPost = false
    var deliveryResult = true
    let holdDelivery: Bool
    let deliveryEntered = NotificationGate(), releaseDelivery = NotificationGate()
    let holdAuthorization: Bool
    let holdPost: Bool
    let authorizationEntered = NotificationGate(), releaseAuthorization = NotificationGate()
    let postEntered = NotificationGate(), releasePost = NotificationGate()
    init(_ status: NotificationAuthorization, holdAuthorization: Bool = false, holdPost: Bool = false, holdDelivery: Bool = false) {
        self.status = status; self.holdAuthorization = holdAuthorization; self.holdPost = holdPost; self.holdDelivery = holdDelivery
    }
    func authorization() async -> NotificationAuthorization {
        await authorizationEntered.open()
        if holdAuthorization { await releaseAuthorization.wait() }
        return status
    }
    func requestAuthorization() async throws { requested += 1; status = .authorized }
    func post(_ notification: MeasurementNotification) async throws {
        if failPost { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "post failed"]) }
        posted.append(notification)
        await postEntered.open()
        if holdPost { await releasePost.wait() }
        if failPost { throw NSError(domain: "fixture", code: 2, userInfo: [NSLocalizedDescriptionKey: "late post failure"]) }
    }
    func remove(_ id: String) async { removed.append(id) }
    func delivered(_ id: String) async -> Bool {
        await deliveryEntered.open()
        if holdDelivery { await releaseDelivery.wait() }
        return deliveryResult && posted.contains { $0.id == id }
    }
    func setDeliveryResult(_ value: Bool) { deliveryResult = value }
    func setPostFailure(_ value: Bool) { failPost = value }
}

@MainActor
final class MeasurementNotificationTests: XCTestCase {
    private func record() -> MeasurementRecord { .init(date: Date(), validDuration: 180, blinkDurations: [0.2, 0.2, 0.2, 0.2, 0.2, 0.2]) }

    func testMeasurementNeverPromptsAndExplicitPermissionAllowsLocalizedDelivery() async {
        for status in [NotificationAuthorization.notDetermined, .denied] {
            let client = NotificationClientFixture(status)
            let controller = MeasurementNotifications(client: client, enabled: true)
            await controller.notify(record(), english: false)?.value
            let posted = await client.posted, requested = await client.requested
            XCTAssertTrue(posted.isEmpty); XCTAssertEqual(requested, 0)
        }
        let client = NotificationClientFixture(.notDetermined)
        let controller = MeasurementNotifications(client: client, enabled: true)
        await controller.refresh()?.value
        XCTAssertEqual(controller.authorization, .notDetermined)
        await controller.requestPermission()?.value
        XCTAssertEqual(controller.authorization, .authorized); XCTAssertFalse(controller.isRequesting)
        let measured = record()
        await controller.notify(measured, english: true)?.value
        let posted = await client.posted, requested = await client.requested
        XCTAssertEqual(requested, 1); XCTAssertEqual(posted.count, 1)
        XCTAssertEqual(posted.first?.id, measured.id.uuidString)
        XCTAssertEqual(posted.first?.title, "Blink measurement complete")
        XCTAssertTrue(posted.first?.body.contains("2.0") == true)
    }

    func testAppModelDisableClearAndShutdownRejectLatePermissionReads() async throws {
        for action in 0...2 {
            let client = NotificationClientFixture(.authorized, holdAuthorization: true)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = AppModel(dataDirectory: root, observesSystemEvents: false, notificationClient: client)
            let pending = model.notifications.notify(record(), english: false)!
            await client.authorizationEntered.wait()
            switch action { case 0: model.setMeasurementNotifications(false); case 1: model.clearMeasurements(); default: model.terminate() }
            await client.releaseAuthorization.open()
            await pending.value
            let posted = await client.posted
            XCTAssertTrue(posted.isEmpty)
            await model.shutdown()
        }
    }

    func testDisableDuringSystemSubmissionRemovesLateDeliveredNotification() async {
        for lateFailure in [false, true] {
            let client = NotificationClientFixture(.authorized, holdPost: true)
            let controller = MeasurementNotifications(client: client, enabled: true)
            let measured = record()
            let pending = controller.notify(measured, english: false)
            await client.postEntered.wait()
            controller.setEnabled(false)
            await client.setPostFailure(lateFailure)
            await client.releasePost.open()
            await pending?.value
            let posted = await client.posted, removed = await client.removed
            XCTAssertEqual(removed, [measured.id.uuidString]); XCTAssertEqual(posted.count, 1)
        }
    }

    func testSubmissionErrorIsVisibleAndTestNotificationDoesNotPretendToBeAMeasurement() async {
        let client = NotificationClientFixture(.authorized)
        let controller = MeasurementNotifications(client: client, enabled: true)
        await client.setPostFailure(true)
        await controller.notify(record(), english: false)?.value
        XCTAssertEqual(controller.lastError, "post failed")
        await client.setPostFailure(false)
        await controller.sendTest(english: false)?.value
        let posted = await client.posted
        XCTAssertEqual(posted.count, 1); XCTAssertTrue(posted.first?.id.hasPrefix("test.") == true)
        XCTAssertEqual(posted.first?.title, "Eyeblink 通知已就绪")
        XCTAssertEqual(controller.testDelivery, .delivered)
        XCTAssertNil(controller.lastError)
        controller.invalidate()
        XCTAssertNil(controller.testDelivery)
    }
    func testProductionDeliveryNeedsSystemReadbackAndTestCannotReplaceIt() async {
        let client = NotificationClientFixture(.authorized)
        await client.setDeliveryResult(false)
        let controller = MeasurementNotifications(client: client, enabled: true)
        await controller.notify(record(), english: false)?.value
        XCTAssertEqual(controller.measurementDelivery, .submitted)
        await controller.sendTest(english: false)?.value
        XCTAssertEqual(controller.testDelivery, .submitted)
        XCTAssertEqual(controller.measurementDelivery, .submitted)
        await client.setDeliveryResult(true)
        await controller.refresh()?.value
        XCTAssertEqual(controller.measurementDelivery, .delivered)
        XCTAssertEqual(controller.testDelivery, .delivered)
    }

    func testLateProductionReadbackCannotSurviveDisableClearOrStop() async {
        for action in 0...2 {
            let client = NotificationClientFixture(.authorized, holdDelivery: true)
            let controller = MeasurementNotifications(client: client, enabled: true)
            let pending = controller.notify(record(), english: false)
            await client.deliveryEntered.wait()
            XCTAssertEqual(controller.measurementDelivery, .submitted)
            switch action { case 0: controller.setEnabled(false); case 1: controller.invalidate(); default: controller.stop() }
            await client.releaseDelivery.open()
            await pending?.value
            XCTAssertNil(controller.measurementDelivery)
        }
    }

}
