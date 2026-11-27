import Charts
import SwiftData
import SwiftUI
import TrackManKit

/// Pick sessions, then a club and a topic, then read the report.
struct DeepDiveFlow: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            SessionPickerView(selected: $selected)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

struct SessionPickerView: View {
    @Binding var selected: Set<String>
    @Query(sort: \StoredActivity.date, order: .reverse) private var activities: [StoredActivity]

    /// Practice sessions with downloaded shots.
    private var sessions: [StoredActivity] {
        activities.filter { $0.shotsFetched && ($0.strokeCount ?? 0) > 0 && Metrics.isFullSwing(typename: $0.typename, kind: $0.kind) }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    quickPick("Last 5") { Set(sessions.prefix(5).map(\.id)) }
                    quickPick("30 days") {
                        let start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                        return Set(sessions.filter { $0.date >= start }.map(\.id))
                    }
                    quickPick("All") { Set(sessions.map(\.id)) }
                    Spacer()
                    if !selected.isEmpty {
                        Button("Clear") { selected = [] }.buttonStyle(.borderless)
                    }
                }
            } footer: {
                Text("Choose the sessions to study. More sessions make the findings steadier.")
            }
            Section("Practice sessions") {
                if sessions.isEmpty {
                    Text("No practice sessions with shots yet. Pull to refresh on Home first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    Button {
                        if selected.contains(session.id) { selected.remove(session.id) } else { selected.insert(session.id) }
                    } label: {
                        HStack {
                            Image(systemName: selected.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(session.id) ? Theme.pine : Color.secondary)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.date, format: .dateTime.weekday().month().day().hour().minute())
                                    .foregroundStyle(Theme.ink)
                                Text(Metrics.kindLabel(session.kind ?? session.typename))
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(session.strokeCount ?? 0) shots").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Deep dive")
        .safeAreaInset(edge: .bottom) {
            NavigationLink {
                TopicPickerView(sessionIDs: selected)
            } label: {
                Text(selected.isEmpty ? "Select sessions" : "Next: \(selected.count) \(selected.count == 1 ? "session" : "sessions")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selected.isEmpty)
            .padding()
            .background(.bar)
        }
    }

    private func quickPick(_ title: String, _ pick: @escaping () -> Set<String>) -> some View {
        Button(title) { selected = pick() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
}

struct TopicPickerView: View {
    let sessionIDs: Set<String>
    @Query private var shots: [StoredShot]
    @State private var club: String?
    @State private var question = ""

    init(sessionIDs: Set<String>) {
        self.sessionIDs = sessionIDs
        let ids = Array(sessionIDs)
        _shots = Query(filter: #Predicate<StoredShot> { ids.contains($0.activityID) }, sort: \StoredShot.date)
    }

    private struct ClubCount: Identifiable {
        let club: String
        let count: Int
        var id: String { club }
    }

    private var clubs: [ClubCount] {
        Dictionary(grouping: shots, by: \.club).map { ClubCount(club: $0.key, count: $0.value.count) }.sorted { $0.count > $1.count }
    }

    var body: some View {
        List {
            Section("Club") {
                Picker("Club", selection: $club) {
                    Text("All clubs (\(shots.count))").tag(String?.none)
                    ForEach(clubs) { entry in
                        Text("\(ClubMetrics.label(entry.club)) (\(entry.count))").tag(Optional(entry.club))
                    }
                }
                .pickerStyle(.navigationLink)
            }
            Section("What to study") {
                ForEach(DeepDiveTopic.allCases) { topic in
                    NavigationLink {
                        DeepDiveReportView(report: DeepDive.run(topic, shots: shots.map(\.record), club: club))
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: topic.symbol)
                                .font(.title3)
                                .foregroundStyle(Theme.pine)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.title).font(.headline).foregroundStyle(Theme.ink)
                                Text(topic.blurb).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            Section {
                TextField("For example: why do my 7 irons go short?", text: $question, axis: .vertical)
                    .lineLimit(2...4)
                    .disabled(true)
            } header: {
                Text("Your own question")
            } footer: {
                Text("Coming next: on-device AI will choose the analysis for questions you type.")
            }
        }
        .navigationTitle("Choose a study")
        .onAppear {
            if club == nil, clubs.contains(where: { DriverMetrics.isDriver($0.club) }) { club = "Driver" }
        }
    }
}

struct DeepDiveReportView: View {
    let report: DeepDiveReport

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("\(report.club.map(ClubMetrics.label) ?? "All clubs") · \(report.shotCount) shots · \(report.sessionCount) \(report.sessionCount == 1 ? "session" : "sessions")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !report.keyStats.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(report.keyStats) { stat in
                            StatTile(label: stat.label, value: stat.value, detail: stat.detail)
                        }
                    }
                }
                if !report.findings.isEmpty {
                    DashboardCard(title: "What the numbers say", subtitle: "Computed from your shots", headline: nil, showsChevron: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(report.findings, id: \.self) { finding in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle().fill(Theme.flag).frame(width: 8, height: 8).padding(.top, 6)
                                    Text(finding).foregroundStyle(Theme.ink)
                                }
                            }
                        }
                    }
                }
                ForEach(report.charts) { chart in
                    DashboardCard(title: chart.title, subtitle: subtitle(chart), headline: nil, showsChevron: false) {
                        DeepDiveChartView(chart: chart)
                    }
                }
                if !report.missing.isEmpty {
                    Text("Not measured in these sessions: \(report.missing.map(\.label).joined(separator: ", ")). TrackMan only records some numbers with certain setups.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if report.keyStats.isEmpty {
                    Text("Nothing to analyze: these shots have none of the numbers this study needs.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(report.topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func subtitle(_ chart: DeepDiveChart) -> String {
        switch chart {
        case .histogram(_, let metric, _): return "How often each \(metric.label.lowercased()) occurs"
        case .trend: return "Average per session"
        case .scatter(_, let r):
            return r.correlation.map { "Each dot is a shot · r = \($0.formatted(.number.precision(.fractionLength(2))))" } ?? "Each dot is a shot"
        case .buckets: return "Share of shots"
        case .strikeMap: return "Impact on the face, as you look at it"
        }
    }
}

struct DeepDiveChartView: View {
    let chart: DeepDiveChart

    var body: some View {
        switch chart {
        case .histogram(_, let metric, let bins):
            Chart(bins) { bin in
                BarMark(x: .value(metric.label, bin.mid), y: .value("Shots", bin.count), width: .ratio(0.9))
                    .foregroundStyle(Theme.fairway)
            }
            .chartXAxisLabel(metric.unit)
            .frame(height: 160)

        case .trend(_, let metric, let points):
            Chart(points) { point in
                LineMark(x: .value("Session", point.date), y: .value(metric.label, point.mean))
                    .foregroundStyle(Theme.pine)
                PointMark(x: .value("Session", point.date), y: .value(metric.label, point.mean))
                    .foregroundStyle(point.id == points.last?.id ? Theme.flag : Theme.pine)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxisLabel(metric.unit)
            .frame(height: 160)

        case .scatter(_, let r):
            let xs = r.points.map(\.x)
            Chart {
                ForEach(Array(r.points.enumerated()), id: \.offset) { _, p in
                    PointMark(x: .value(r.x.label, p.x), y: .value(r.y.label, p.y))
                        .foregroundStyle(Theme.fairway.opacity(0.8))
                        .symbolSize(24)
                }
                if let slope = r.slope, let intercept = r.intercept, let lo = xs.min(), let hi = xs.max() {
                    LineMark(x: .value(r.x.label, lo), y: .value(r.y.label, intercept + slope * lo), series: .value("Fit", "fit"))
                        .foregroundStyle(Theme.pine)
                    LineMark(x: .value(r.x.label, hi), y: .value(r.y.label, intercept + slope * hi), series: .value("Fit", "fit"))
                        .foregroundStyle(Theme.pine)
                }
            }
            .chartXAxisLabel("\(r.x.label) (\(r.x.unit))")
            .chartYAxisLabel("\(r.y.label) (\(r.y.unit))")
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 220)

        case .buckets(_, let buckets):
            VStack(spacing: 8) {
                ForEach(buckets) { bucket in
                    HStack {
                        Text(bucket.label).font(.subheadline).frame(width: 80, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Theme.pine.opacity(0.15))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Theme.pine).frame(width: max(4, geo.size.width * bucket.share))
                                }
                        }
                        .frame(height: 12)
                        Text("\(Int((bucket.share * 100).rounded()))%")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

        case .strikeMap(_, let points):
            Chart {
                RuleMark(x: .value("Center", 0)).foregroundStyle(Theme.ink.opacity(0.2))
                RuleMark(y: .value("Center", 0)).foregroundStyle(Theme.ink.opacity(0.2))
                ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                    PointMark(x: .value("Toe/heel", p.x), y: .value("High/low", p.y))
                        .foregroundStyle(abs(p.x) <= 10 && abs(p.y) <= 10 ? Theme.pine : Theme.flag)
                        .symbolSize(30)
                }
            }
            .chartXScale(domain: -35...35)
            .chartYScale(domain: -25...25)
            .chartXAxisLabel("heel · mm · toe")
            .frame(height: 200)
        }
    }
}
