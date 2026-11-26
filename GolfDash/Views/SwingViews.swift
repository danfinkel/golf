import Charts
import SwiftUI
import TrackManKit

struct SwingsCard: View {
    let days: [DailySwings]

    private var total: Int { days.map(\.count).reduce(0, +) }

    var body: some View {
        DashboardCard(
            title: "Swings per day",
            subtitle: "Full swings, last \(days.count) days",
            headline: total.formatted()
        ) {
            if total == 0 {
                EmptyChartText("No full-swing sessions in the last \(days.count) days.")
            } else {
                Chart(days) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Swings", day.count)
                    )
                    .foregroundStyle(day.day == days.last?.day ? Theme.pine : Theme.fairway)
                }
                .frame(height: 140)
            }
        }
    }
}

struct SwingsDetailView: View {
    let days: [DailySwings]

    private struct Slice: Identifiable {
        let day: Date
        let kind: String
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(kind)" }
    }

    private var slices: [Slice] {
        days.flatMap { day in
            day.byKind.sorted { $0.key < $1.key }.map { Slice(day: day.day, kind: $0.key, count: $0.value) }
        }
    }

    private var activeDays: [DailySwings] { days.filter { $0.count > 0 }.reversed() }

    var body: some View {
        List {
            Section {
                Chart(slices) { slice in
                    BarMark(
                        x: .value("Day", slice.day, unit: .day),
                        y: .value("Swings", slice.count)
                    )
                    .foregroundStyle(by: .value("Session", slice.kind))
                }
                .chartLegend(position: .bottom)
                .frame(height: 240)
                Text("Putting sessions are excluded. Days use your phone's time zone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Days with swings") {
                if activeDays.isEmpty {
                    Text("None in the last \(days.count) days.").foregroundStyle(.secondary)
                }
                ForEach(activeDays) { day in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(day.day, format: .dateTime.weekday(.wide).month().day())
                            Text(day.byKind.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: " · "))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(day.count.formatted()).monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Swings per day")
    }
}
