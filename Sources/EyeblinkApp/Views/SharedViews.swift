import SwiftUI

struct PageIntroduction: View {
    var title: String
    var detail: String
    var symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.system(size: 27, weight: .regular))
                .foregroundStyle(.teal)
                .frame(width: 43, height: 43)
                .background(.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.title2.weight(.semibold))
                Text(detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct IntervalField: View {
    var title: String
    @Binding var seconds: TimeInterval
    var unit: String
    var divisor: Double = 1
    var range: ClosedRange<Double> = 1...3600
    var step: Double = 1
    private var value: Binding<Double> {
        Binding(get: { seconds / divisor }, set: { seconds = min(range.upperBound, max(range.lowerBound, $0)) * divisor })
    }
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 16)
            HStack(spacing: 7) {
                TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 62)
                    .accessibilityLabel(title)
                Text(unit).foregroundStyle(.secondary)
                Stepper(value: value, in: range, step: step) { EmptyView() }.labelsHidden().fixedSize()
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(seconds / divisor)) \(unit)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct ContextNote: View {
    var text: String
    var symbol: String = "info.circle"
    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

struct MetricValue: View {
    var title: String
    var value: String
    var unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 28, weight: .medium, design: .rounded))
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
