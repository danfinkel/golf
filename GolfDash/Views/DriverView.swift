import Charts
import SwiftData
import SwiftUI
import TrackManKit

/// Everything about the driver: course drive distance and fairways from
/// rounds, plus shot-by-shot numbers from practice sessions.
struct DriverView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @ObservedObject var sync: SyncService
    @Query(sort: \StoredRound.date) private var rounds: [StoredRound]
    @Query(filter: #Predicate<StoredShot> { $0.club == "Driver" }, sort: \StoredShot.date) private var drives: [StoredShot]
    @State private var range: PracticeRange = .ninety

    enum PracticeRange: String, CaseIterable, Identifiable {
        case thirty = "30 days", ninety = "90 days", all = "All"
        var id: String { rawValue }
        var start: Date? {
            switch self {
            case .thirty: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .ninety: return Calendar.current.date(byAdding: .day, value: -90, to: Date())
            case .all: return nil
            }
        }
    }

    private var trend: [DrivePoint] { Metrics.driveTrend(rounds.map(\.sample)) }
    private var shots: [ShotSample] {
        let all = drives.map(\.sample)
        guard let start = range.start else { return all }
        return all.filter { $0.date >= start }
    }
    private var summary: DriverSummary { DriverMetrics.summary(shots) }
    private var fairways: FairwaySplit {
        DriverMetrics.fairways(rounds.map { (hit: $0.fairwaysHit, left: $0.fairwaysLeft, right: $0.fairwaysRight) })
    }
    private var longestOnCourse: Double? {
        rounds.compactMap(\.driveMaxMeters).max().map(Units.yards(fromMeters:))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SyncStatusView(sync: sync)

                    SectionTitle("On the course")
                    NavigationLink {
                        DriveDetailView(rounds: rounds)
                    } label: {
                        DriveCard(points: trend)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 12) {
                        StatTile(label: "Longest drive", value: Format.yards(longestOnCourse) ?? "–", detail: "In a round")
                        StatTile(label: "Fairways hit", value: Format.percent(fairways.hitShare) ?? "–",
                                 detail: fairways.total > 0 ? "\(fairways.hit) of \(fairways.total) tee shots" : "No fairway data yet")
                    }
                    if fairways.total > 0 {
                        FairwayCard(split: fairways)
                    }

                    SectionTitle("In practice")
                    Picker("Range", selection: $range) {
                        ForEach(PracticeRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if summary.shots == 0 {
                        DashboardCard(title: "No driver shots", subtitle: "Hit a few drivers in a TrackMan session and pull to refresh.", headline: nil, showsChevron: false) {
                            EmptyView()
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            StatTile(label: "Carry", value: Format.yards(summary.carryYards) ?? "–",
                                     detail: Format.yards(summary.totalYards).map { "\($0) total" })
                            StatTile(label: "Ball speed", value: Format.mph(summary.ballSpeedMph) ?? "–",
                                     detail: summary.smashFactor.map { "Smash \($0.formatted(.number.precision(.fractionLength(2))))" })
                            StatTile(label: "Club speed", value: Format.mph(summary.clubSpeedMph) ?? "–",
                                     detail: summary.attackAngle.map { "Attack \(Format.degrees($0))" })
                            StatTile(label: "Launch", value: summary.launchAngle.map(Format.degrees) ?? "–",
                                     detail: summary.spinRate.map { "\(Int($0.rounded()).formatted()) rpm spin" })
                        }
                        PracticeTrendCard(days: DriverMetrics.days(shots))
                        DispersionCard(shots: shots, summary: summary)
                        Text("\(summary.shots) driver shots from practice sessions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Driver")
            .refreshable { await sync.sync(session: session, context: context) }
        }
    }
}

/// Tee-shot results from rounds as one stacked bar: left, fairway, right.
struct FairwayCard: View {
    let split: FairwaySplit

    var body: some View {
        DashboardCard(title: "Where tee shots finish", subtitle: "All course rounds", headline: nil, showsChevron: false) {
            GeometryReader { geo in
                let total = max(Double(split.total), 1)
                HStack(spacing: 2) {
                    segment(Theme.flag, Double(split.left) / total, geo.size.width)
                    segment(Theme.pine, Double(split.hit) / total, geo.size.width)
                    segment(Theme.flag, Double(split.right) / total, geo.size.width)
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            HStack {
                label("Left", split.left)
                Spacer()
                label("Fairway", split.hit)
                Spacer()
                label("Right", split.right)
            }
        }
    }

    private func segment(_ color: Color, _ share: Double, _ width: CGFloat) -> some View {
        color.frame(width: max(0, width * share - 2))
    }

    private func label(_ text: String, _ count: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(Format.percent(Double(count) / Double(max(split.total, 1))) ?? "")")
                .font(Theme.score(.title3)).foregroundStyle(Theme.ink)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Average carry per practice day, with ball speed in the detail.
struct PracticeTrendCard: View {
    let days: [DriverDay]

    var body: some View {
        DashboardCard(title: "Practice carry", subtitle: "Average per session day", headline: Format.yards(days.last?.carryYards), showsChevron: false) {
            if days.count < 2 {
                EmptyChartText("Two or more practice days with driver shots draw a trend.")
            } else {
                Chart(days) { day in
                    if let carry = day.carryYards {
                        LineMark(x: .value("Day", day.day, unit: .day), y: .value("Carry", carry))
                            .foregroundStyle(Theme.pine)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", day.day, unit: .day), y: .value("Carry", carry))
                            .foregroundStyle(day.id == days.last?.id ? Theme.flag : Theme.fairway)
                            .symbolSize(day.id == days.last?.id ? 80 : 30)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("yards")
                .frame(height: 160)
            }
        }
    }
}

/// Where practice drives land: carry against left/right, target line at 0.
struct DispersionCard: View {
    let shots: [ShotSample]
    let summary: DriverSummary

    private struct Dot: Identifiable {
        let id: Int
        let side: Double
        let carry: Double
    }

    private var dots: [Dot] {
        shots.enumerated().compactMap { index, shot in
            guard let side = shot.carrySide, let carry = shot.carry else { return nil }
            return Dot(id: index, side: Units.yards(fromMeters: side), carry: Units.yards(fromMeters: carry))
        }
    }

    var body: some View {
        DashboardCard(
            title: "Dispersion",
            subtitle: summary.sideSpreadYards.map { "Spread ±\(Int($0.rounded())) yd left to right" } ?? "Left and right of target",
            headline: nil,
            showsChevron: false
        ) {
            let limit = max(30, (dots.map { abs($0.side) }.max() ?? 30).rounded(.up))
            Chart {
                RuleMark(x: .value("Target", 0))
                    .foregroundStyle(Theme.ink.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                ForEach(dots) { dot in
                    PointMark(x: .value("Side", dot.side), y: .value("Carry", dot.carry))
                        .foregroundStyle(abs(dot.side) > DriverMetrics.missYards ? Theme.flag : Theme.pine)
                        .opacity(0.75)
                        .symbolSize(28)
                }
            }
            .chartXScale(domain: -limit...limit)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxisLabel("yards left · right")
            .chartYAxisLabel("carry")
            .frame(height: 220)
            HStack {
                Text("Miss left \(Format.percent(summary.missLeftShare) ?? "–")")
                Spacer()
                Text("Miss right \(Format.percent(summary.missRightShare) ?? "–")")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("A miss is more than \(Int(DriverMetrics.missYards)) yards off line.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
