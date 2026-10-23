import SwiftUI
import Charts
import EyeblinkCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    var historyOnly = false
    @Environment(\.openWindow) private var openWindow
    @State private var period: HistoryPeriod = .week
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var throughDate = Date()
    @State private var selectedDate: Date?
    @State private var showClearConfirmation = false

    private enum HistoryPeriod: String, CaseIterable { case week, month, all, custom }
    private var records: [MeasurementRecord] {
        switch period {
        case .week: return StatisticsSummary.filter(model.measurements, from: Calendar.current.date(byAdding: .day, value: -6, to: Date()), through: Date())
        case .month: return StatisticsSummary.filter(model.measurements, from: Calendar.current.date(byAdding: .day, value: -29, to: Date()), through: Date())
        case .all: return model.measurements.sorted { $0.date < $1.date }
        case .custom: return StatisticsSummary.filter(model.measurements, from: fromDate, through: throughDate)
        }
    }
    private var summary: StatisticsSummary { StatisticsSummary(records: records) }
    private var selectedRecord: MeasurementRecord? {
        guard let selectedDate else { return nil }
        return records.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        Form {
            Section {
                PageIntroduction(title: model.text("了解自己的眨眼节奏", "Get to know your blink rhythm"), detail: model.text("用真实测量观察变化，专注于习惯，而不是分数。", "Notice patterns in your measurements and build a comfortable habit."), symbol: "chart.xyaxis.line")
            }
            if !historyOnly {
            Section {
                Toggle(model.text("定期测量眨眼频率", "Measure blink frequency regularly"), isOn: $model.settings.measurementEnabled)
                LabeledContent(model.text("测量间隔", "Measurement interval")) {
                    Text(model.text("30 分钟", "30 minutes")).foregroundStyle(.secondary)
                }
                LabeledContent(model.text("单次测量时长", "Measurement duration")) {
                    Text(model.text("3 分钟", "3 minutes")).foregroundStyle(.secondary)
                }
                Toggle(model.text("测量完成后通知我", "Notify me when a measurement finishes"), isOn: Binding(get: { model.settings.measurementNotifications }, set: model.setMeasurementNotifications))
                    .disabled(!model.settings.measurementEnabled)
                NotificationSettingsRow(notifications: model.notifications, english: model.isEnglish, enabled: model.settings.measurementNotifications && model.settings.measurementEnabled)
                if model.isMeasuring {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(model.text("正在测量", "Measuring"))
                            Spacer()
                            Text(model.measurementProgress, format: .percent.precision(.fractionLength(0))).foregroundStyle(.secondary)
                        }
                        ProgressView(value: model.measurementProgress).accessibilityLabel(model.text("测量进度", "Measurement progress"))
                        Text(model.text("请保持画面中只有一张脸。持续未检测到人脸时，本次测量会停止。", "Keep one face in view. Measurement stops if a face cannot be detected for a sustained period.")).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else {
                    HStack {
                        Text(model.cameraStatus).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.text("立即测量", "Measure now"), action: model.startMeasurement)
                            .buttonStyle(.borderedProminent)
                            .disabled(model.isPaused || model.isCameraPaused || !model.cameraAuthorized || !model.settings.cameraEnabled || model.isClearingMeasurements)
                    }
                }
            } header: { Text(model.text("测量", "Measurement")) }

            }

            Section {
                if !historyOnly {
                    HStack {
                        Spacer()
                        Button(model.text("在独立窗口中查看", "Open in a separate window")) { openWindow(id: "history") }
                    }
                }
                Picker(model.text("时间范围", "Date range"), selection: $period) {
                    Text(model.text("近 7 天", "7 days")).tag(HistoryPeriod.week)
                    Text(model.text("近 30 天", "30 days")).tag(HistoryPeriod.month)
                    Text(model.text("全部", "All time")).tag(HistoryPeriod.all)
                    Text(model.text("自定义", "Custom")).tag(HistoryPeriod.custom)
                }.pickerStyle(.segmented).labelsHidden()
                if period == .custom {
                    HStack {
                        DatePicker(model.text("从", "From"), selection: $fromDate, in: ...throughDate, displayedComponents: .date)
                        DatePicker(model.text("至", "Through"), selection: $throughDate, in: fromDate..., displayedComponents: .date)
                    }
                }
                if records.isEmpty {
                    ContentUnavailableView {
                        Label(model.text("还没有测量记录", "No measurements yet"), systemImage: "chart.xyaxis.line")
                    } description: {
                        Text(model.measurements.isEmpty ? model.text("允许摄像头权限后，点击“立即测量”开始第一次记录。", "Allow camera access, then choose Measure now to start your first record.") : model.text("这个时间范围内没有记录，试试其他日期。", "No records in this date range. Try a different range."))
                    }
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    HStack(spacing: 20) {
                        MetricValue(title: model.text("平均频率", "Average frequency"), value: number(summary.meanBPM), unit: model.text("次/分", "blinks/min"))
                        MetricValue(title: records.last?.isEstimated == true ? model.text("最近一次（单眼估计）", "Latest (single-eye estimate)") : model.text("最近一次", "Latest frequency"), value: number(records.last?.blinksPerMinute), unit: model.text("次/分", "blinks/min"))
                        MetricValue(title: model.text("平均眨眼时长", "Average blink duration"), value: number(summary.meanBlinkDurationMilliseconds, digits: 0), unit: model.text("毫秒", "ms"))
                    }.padding(.vertical, 10)
                    if records.contains(where: \.isEstimated) {
                        Text(model.text("橙色点为单眼估计，不计入平均频率和平均眨眼时长。", "Orange points are single-eye estimates, excluded from mean frequency and mean blink duration."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    historyChart
                    HStack {
                        if let record = selectedRecord {
                            Text(record.date, format: .dateTime.month().day().hour().minute())
                            if record.isEstimated { Text(model.text("单眼估计", "Single-eye estimate")) }
                            Spacer()
                            Text("\(number(record.blinksPerMinute)) \(model.text("次/分", "blinks/min"))")
                            Text("· \(number(record.averageBlinkDurationMilliseconds, digits: 0)) \(model.text("毫秒", "ms"))")
                        } else {
                            Text(model.text("将鼠标移到图表，可查看测量明细。", "Move the pointer over the chart to inspect a measurement."))
                            Spacer()
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(height: 24).accessibilityElement(children: .combine)
                    DisclosureGroup(model.text("测量记录（\(records.count)）", "Measurements (\(records.count))")) {
                        ForEach(records.reversed()) { record in
                            LabeledContent {
                                Text("\(number(record.blinksPerMinute)) \(model.text("次/分", "blinks/min")) · \(number(record.averageBlinkDurationMilliseconds, digits: 0)) \(model.text("毫秒", "ms"))")
                                    .foregroundStyle(.secondary)
                            } label: {
                                HStack {
                                    Text(record.date, format: .dateTime.year().month().day().hour().minute())
                                    if record.isEstimated { Text(model.text("单眼估计", "Single-eye estimate")).foregroundStyle(.orange) }
                                }
                            }
                        }
                    }
                }
            } header: { Text(model.text("历史趋势", "History")) } footer: {
                Text(model.text("测量记录保存在这台 Mac 上。", "Measurements stay on this Mac."))
            }
            if !model.measurements.isEmpty {
                Section {
                    Button(model.text("清空所有测量记录…", "Clear all measurements…"), role: .destructive) { showClearConfirmation = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(model.text("清空所有测量记录？", "Clear all measurements?"), isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button(model.text("清空记录", "Clear measurements"), role: .destructive, action: model.clearMeasurements)
            Button(model.text("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(model.text("本机保存的全部历史记录将被删除，此操作无法撤销。", "All history stored on this Mac will be deleted. This cannot be undone."))
        }
    }

    private var historyChart: some View {
        Chart {
            RuleMark(y: .value(model.text("原版参考线", "Original reference"), 10.0))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text(model.text("原版参考 · 10 次/分", "Original reference · 10 blinks/min")).font(.caption2).foregroundStyle(.secondary)
                }
            if let mean = summary.meanBPM {
                RuleMark(y: .value(model.text("平均频率", "Average rate"), mean))
                    .foregroundStyle(.teal.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            ForEach(records) { record in
                if !record.isEstimated {
                    LineMark(x: .value(model.text("时间", "Date"), record.date), y: .value(model.text("每分钟眨眼", "Blinks per minute"), record.blinksPerMinute))
                        .foregroundStyle(.teal).interpolationMethod(.linear)
                }
                PointMark(x: .value(model.text("时间", "Date"), record.date), y: .value(model.text("每分钟眨眼", "Blinks per minute"), record.blinksPerMinute))
                    .foregroundStyle(record.isEstimated ? Color.orange : Color.teal).symbolSize(28)
                    .accessibilityLabel(record.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("\(number(record.blinksPerMinute)) \(model.text("次/分", "blinks per minute"))\(record.isEstimated ? model.text("，单眼估计", ", single-eye estimate") : "")")
            }
            if let record = selectedRecord {
                RuleMark(x: .value(model.text("选中时间", "Selected date"), record.date))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ChartPointerSurface { point in
                    guard let point, let anchor = proxy.plotFrame else { selectedDate = nil; return }
                    let plot = geometry[anchor]
                    selectedDate = plot.contains(point) ? proxy.value(atX: point.x - plot.minX, as: Date.self) : nil
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .chartYScale(domain: 0...max(25, (records.map(\.blinksPerMinute).max() ?? 0) * 1.15))
        .chartYAxisLabel(model.text("次/分", "blinks/min"))
        .frame(height: 220)
        .padding(.top, 12)
    }

    private func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(digits)))
    }
}
