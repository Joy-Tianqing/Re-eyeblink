import Foundation
import Combine
import UserNotifications
import EyeblinkCore

enum NotificationAuthorization: Equatable, Sendable {
    case unknown, notDetermined, denied, authorized, provisional
    var canDeliver: Bool { self == .authorized || self == .provisional }
}

struct MeasurementNotification: Sendable, Equatable {
    let id: String
    let title: String
    let body: String
}

protocol MeasurementNotificationClient: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws
    func post(_ notification: MeasurementNotification) async throws
    func delivered(_ id: String) async -> Bool
    func remove(_ id: String) async
}

/// UNUserNotificationCenter is thread-safe; this adapter has no mutable app state.
final class SystemMeasurementNotificationClient: NSObject, MeasurementNotificationClient, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private let center = UNUserNotificationCenter.current()
    override init() { super.init(); center.delegate = self }
    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        @unknown default: return .unknown
        }
    }
    func requestAuthorization() async throws { _ = try await center.requestAuthorization(options: [.alert]) }
    func post(_ notification: MeasurementNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title; content.body = notification.body
        try await center.add(UNNotificationRequest(identifier: notification.id, content: content, trigger: nil))
    }
    func remove(_ id: String) async { center.removeDeliveredNotifications(withIdentifiers: [id]) }
    func delivered(_ id: String) async -> Bool { await center.deliveredNotifications().contains { $0.request.identifier == id } }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

/// Permission prompts are explicit UI actions. A measurement only delivers when
/// already authorized, and late callbacks cannot outlive disable/clear/shutdown.
@MainActor
final class MeasurementNotifications: ObservableObject {
    @Published private(set) var authorization: NotificationAuthorization = .unknown
    @Published private(set) var isRequesting = false
    @Published private(set) var lastError: String?
    @Published private(set) var testDelivery: DeliveryState?
    @Published private(set) var measurementDelivery: DeliveryState?
    enum DeliveryState { case submitted, delivered }
    private let client: (any MeasurementNotificationClient)?
    private var enabled: Bool
    private var closed = false
    private var generation = 0
    private var statusRevision = 0
    private var testID: String?
    private var measurementID: String?
    private var permissionTask: Task<Void, Never>?
    private var deliveries: [UUID: Task<Void, Never>] = [:]

    init(client: (any MeasurementNotificationClient)?, enabled: Bool) { self.client = client; self.enabled = enabled }
    func setEnabled(_ value: Bool) {
        if enabled != value { enabled = value; if !value { invalidate() } }
    }
    func invalidate() { generation += 1; testID = nil; testDelivery = nil; measurementID = nil; measurementDelivery = nil; deliveries.values.forEach { $0.cancel() } }
    func stop() { closed = true; invalidate(); permissionTask?.cancel() }

    @discardableResult func refresh() -> Task<Void, Never>? {
        guard let client, !closed, !isRequesting else { return nil }
        statusRevision += 1; let revision = statusRevision
        return Task {
            let status = await client.authorization()
            guard !closed, revision == statusRevision else { return }
            authorization = status
            let stamp = generation
            for (id, isTest) in [(testID, true), (measurementID, false)] {
                guard let id else { continue }
                let delivered = await client.delivered(id)
                guard current(stamp), revision == statusRevision else { return }
                if delivered { recordDelivery(id, isTest: isTest, state: .delivered) }
            }
        }
    }
    @discardableResult func requestPermission() -> Task<Void, Never>? {
        guard let client, enabled, !closed, !isRequesting else { return nil }
        statusRevision += 1; let revision = statusRevision
        isRequesting = true; lastError = nil
        let task = Task {
            defer { if !closed { isRequesting = false } }
            do {
                try await client.requestAuthorization()
                let status = await client.authorization()
                guard !closed, revision == statusRevision else { return }
                authorization = status
            } catch { if !closed { lastError = error.localizedDescription } }
        }
        permissionTask = task
        return task
    }

    @discardableResult func notify(_ record: MeasurementRecord, english: Bool) -> Task<Void, Never>? {
        deliver(.init(id: record.id.uuidString,
            title: english ? "Blink measurement complete" : "眨眼测量已完成",
            body: english ? String(format: "Blink rate: %.1f blinks per minute.", record.bpm) : String(format: "本次眨眼频率 %.1f 次/分钟。", record.bpm)))
    }
    @discardableResult func sendTest(english: Bool) -> Task<Void, Never>? {
        let id = "test." + UUID().uuidString
        return deliver(.init(id: id,
            title: english ? "Eyeblink notifications are ready" : "Eyeblink 通知已就绪",
            body: english ? "This is a test notification. It does not create a measurement." : "这是一条测试通知，不会新增测量记录。"), isTest: true)
    }
    private func current(_ stamp: Int) -> Bool { !closed && enabled && stamp == generation && !Task.isCancelled }
    private func deliver(_ notification: MeasurementNotification, isTest: Bool = false) -> Task<Void, Never>? {
        guard let client, enabled, !closed else { return nil }
        lastError = nil
        if isTest { testID = notification.id; testDelivery = nil }
        else { measurementID = notification.id; measurementDelivery = nil }
        let stamp = generation, id = UUID()
        let task = Task {
            defer { deliveries.removeValue(forKey: id) }
            let status = await client.authorization()
            guard current(stamp), status.canDeliver else { return }
            do {
                try await client.post(notification)
                if !current(stamp) { await client.remove(notification.id) }
                else {
                    recordDelivery(notification.id, isTest: isTest, state: .submitted)
                    let delivered = await client.delivered(notification.id)
                    if current(stamp), delivered { recordDelivery(notification.id, isTest: isTest, state: .delivered) }
                }
            } catch {
                if current(stamp) { lastError = error.localizedDescription }
                else { await client.remove(notification.id) }
            }
        }
        deliveries[id] = task
        return task
    }
    private func recordDelivery(_ id: String, isTest: Bool, state: DeliveryState) {
        if isTest, testID == id { testDelivery = state }
        else if !isTest, measurementID == id { measurementDelivery = state }
    }

}
