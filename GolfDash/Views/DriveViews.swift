import Charts
import SwiftData
import SwiftUI
import TrackManKit

struct DriveCard: View {
    let points: [DrivePoint]

    var body: some View {
        DashboardCard(
            title: "Average drive",
            subtitle: "Course rounds, \(Metrics.rollingWindow)-round average",
            headline: Format.yards(Metrics.headlineDrive(points))
        ) {
            if points.isEmpty {
                EmptyChartText("No course rounds with drive data yet.")
            } else {
                DriveChart(points: points)
                    .frame(height: 160)
            }
        }
    }
}

struct DriveChart: View {
    let points: [DrivePoint]

    var body: some View {
        Chart {
            ForEach(points) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Yards", point.yards)
                )
                .foregroundStyle(Theme.fairway.opacity(0.7))
                .symbolSize(24)
            }
            ForEach(points.filter { $0.rollingYards != nil }) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Rolling average", point.rollingYards ?? 0)
                )
                .foregroundStyle(Theme.pine)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .interpolationMethod(.monotone)
            }
            if let latest = points.last(where: { $0.rollingYards != nil }), let yards = latest.rollingYards {
                PointMark(
                    x: .value("Date", latest.date),
                    y: .value("Rolling average", yards)
                )
                .foregroundStyle(Theme.flag)
                .symbolSize(90)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxisLabel("yards")
    }
}

struct DriveDetailView: View {
    let rounds: [StoredRound]
    @State private var range: DateRange = .all

    enum DateRange: String, CaseIterable, Identifiable {
        case threeMonths = "3M", sixMonths = "6M", all = "All"
        var id: String { rawValue }

        var start: Date? {
            switch self {
            case .threeMonths: return Calendar.current.date(byAdding: .month, value: -3, to: Date())
            case .sixMonths: return Calendar.current.date(byAdding: .month, value: -6, to: Date())
            case .all: return nil
            }
        }
    }

    /// Rolling values are computed over all rounds first, so the first rounds
    /// inside a short range still carry their average.
    private var points: [DrivePoint] {
        let all = Metrics.driveTrend(rounds.map(\.sample))
        guard let start = range.start else { return all }
        return all.filter { $0.date >= start }
    }

    private var roundsByID: [String: StoredRound] {
        Dictionary(rounds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $range) {
                    ForEach(DateRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if points.isEmpty {
                    EmptyChartText("No rounds with drive data in this range.")
                } else {
                    DriveChart(points: points).frame(height: 240)
                    Text("Dots are each round's drive average. The line is the average of the last \(Metrics.rollingWindow) rounds.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Rounds") {
                ForEach(points.reversed()) { point in
                    let round = roundsByID[point.id]
                    NavigationLink {
                        if let round { RoundDetailView(round: round) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(round?.courseName ?? "Course round")
                                Text("\(point.date, format: .dateTime.month().day().year())\(round?.holesPlayed.map { " · \($0) holes" } ?? "")")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Format.yards(point.yards) ?? "").monospacedDigit()
                                if let max = Format.yards(round?.driveMaxMeters.map(Units.yards(fromMeters:))) {
                                    Text("max \(max)").font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Average drive")
    }
}

struct EmptyChartText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }
}
