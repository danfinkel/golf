import SwiftData
import SwiftUI
import TrackManKit

/// The Rounds tab: every finished round, newest first.
struct RoundsView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @ObservedObject var sync: SyncService
    @Query(sort: \StoredRound.date, order: .reverse) private var allRounds: [StoredRound]

    private var rounds: [StoredRound] { allRounds.filter(\.isFinished) }
    private var eighteens: [Int] { rounds.filter { $0.holesPlayed == 18 }.compactMap(\.grossScore) }
    private var nines: [Int] { rounds.filter { $0.holesPlayed == 9 }.compactMap(\.grossScore) }

    private struct MonthGroup: Identifiable {
        let month: Date
        let rounds: [StoredRound]
        var id: Date { month }
    }

    /// Rounds grouped by month, newest month first.
    private var months: [MonthGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: rounds) { calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { MonthGroup(month: $0, rounds: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(label: "Rounds", value: "\(rounds.count)",
                                 detail: "\(eighteens.count) of 18, \(nines.count) of 9")
                        StatTile(label: "Best score", value: eighteens.min().map { "\($0)" } ?? "–",
                                 detail: nines.min().map { "Best 9: \($0)" } ?? "18 holes")
                        StatTile(label: "18-hole average", value: average(eighteens) ?? "–",
                                 detail: eighteens.isEmpty ? "No 18-hole rounds" : "\(eighteens.count) rounds")
                        StatTile(label: "9-hole average", value: average(nines) ?? "–",
                                 detail: nines.isEmpty ? "No 9-hole rounds" : "\(nines.count) rounds")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if rounds.isEmpty {
                    Text("No finished rounds yet. Rounds count when TrackMan marks them complete or when you play a full 9 or 18.")
                        .foregroundStyle(.secondary)
                }
                ForEach(months) { group in
                    Section(group.month.formatted(.dateTime.month(.wide).year())) {
                        ForEach(group.rounds) { round in
                            NavigationLink {
                                RoundDetailView(round: round)
                            } label: {
                                RoundRow(round: round)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Rounds")
            .refreshable { await sync.sync(session: session, context: context) }
        }
    }

    private func average(_ scores: [Int]) -> String? {
        guard !scores.isEmpty else { return nil }
        return (Double(scores.reduce(0, +)) / Double(scores.count)).formatted(.number.precision(.fractionLength(1)))
    }
}

struct RoundRow: View {
    let round: StoredRound

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName ?? "Course round").foregroundStyle(Theme.ink)
                Text([round.date.formatted(.dateTime.weekday().month().day()), round.holesPlayed.map { "\($0) holes" }, round.teeName.map { "\($0) tees" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(round.grossScore.map { "\($0)" } ?? "–").font(Theme.score(.title2)).foregroundStyle(Theme.pine)
                if let toPar = round.toParLabel {
                    Text(toPar).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One round: the score, the key stats and the scorecard.
struct RoundDetailView: View {
    let round: StoredRound

    private var fairways: String? {
        guard let hit = round.fairwaysHit else { return nil }
        let total = hit + (round.fairwaysLeft ?? 0) + (round.fairwaysRight ?? 0)
        return total > 0 ? "\(hit) of \(total)" : nil
    }

    private var greens: String? {
        guard let gir = round.greensInRegulation, let holes = round.holesPlayed, holes > 0 else { return nil }
        return "\(gir) of \(holes)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(label: "Putts", value: round.putts.map { "\($0)" } ?? "–",
                             detail: perHole(round.putts).map { "\($0) per hole" })
                    StatTile(label: "Fairways", value: fairways ?? "–",
                             detail: fairwayMisses)
                    StatTile(label: "Greens in reg", value: greens ?? "–", detail: nil)
                    StatTile(label: "Drive", value: Format.yards(round.driveAverageMeters.map(Units.yards(fromMeters:))) ?? "–",
                             detail: Format.yards(round.driveMaxMeters.map(Units.yards(fromMeters:))).map { "Longest \($0)" })
                }
                ScoringMixCard(round: round)
                ScorecardView(holes: round.holes)
            }
            .padding()
        }
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(round.courseName ?? "Round")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(round.courseName ?? "Course round").font(Theme.display(.title2)).foregroundStyle(Theme.ink)
                Text([round.date.formatted(.dateTime.weekday(.wide).month().day().year()),
                      round.teeName.map { "\($0) tees" },
                      round.holesPlayed.map { "\($0) holes" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let hcp = round.courseHandicap {
                    Text("Course handicap \(Format.handicap(hcp))\(round.netScore.map { " · net \($0)" } ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(round.grossScore.map { "\($0)" } ?? "–").font(Theme.score(.largeTitle)).foregroundStyle(Theme.pine)
                if let toPar = round.toParLabel {
                    Text(toPar).font(Theme.score(.title3)).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var fairwayMisses: String? {
        guard let left = round.fairwaysLeft, let right = round.fairwaysRight, left + right > 0 else { return nil }
        return "Missed \(left) left, \(right) right"
    }

    private func perHole(_ value: Int?) -> String? {
        guard let value, let holes = round.holesPlayed, holes > 0 else { return nil }
        return (Double(value) / Double(holes)).formatted(.number.precision(.fractionLength(1)))
    }
}

/// Birdies, pars, bogeys and worse as one stacked bar.
struct ScoringMixCard: View {
    let round: StoredRound

    private struct Part: Identifiable {
        let label: String
        let count: Int
        let color: Color
        var id: String { label }
    }

    private var parts: [Part] {
        [
            Part(label: "Eagle+", count: round.eagles ?? 0, color: Theme.flag),
            Part(label: "Birdie", count: round.birdies ?? 0, color: Theme.flag.opacity(0.7)),
            Part(label: "Par", count: round.pars ?? 0, color: Theme.pine),
            Part(label: "Bogey", count: round.bogeys ?? 0, color: Theme.fairway),
            Part(label: "Double", count: round.doubleBogeys ?? 0, color: Theme.ink.opacity(0.45)),
            Part(label: "Triple+", count: round.triplesOrWorse ?? 0, color: Theme.ink.opacity(0.7)),
        ].filter { $0.count > 0 }
    }

    var body: some View {
        let total = parts.map(\.count).reduce(0, +)
        if total > 0 {
            DashboardCard(title: "Scoring", subtitle: "Holes by result", headline: nil, showsChevron: false) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(parts) { part in
                            part.color.frame(width: max(0, geo.size.width * Double(part.count) / Double(total) - 2))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(Capsule())
                HStack {
                    ForEach(parts) { part in
                        VStack(spacing: 0) {
                            Text("\(part.count)").font(Theme.score(.title3)).foregroundStyle(Theme.ink)
                            Text(part.label).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// A printed-style scorecard, one block per nine. Birdies are circled and
/// bogeys boxed, as on a paper card.
struct ScorecardView: View {
    let holes: [Scorecard.Hole]

    var body: some View {
        let nines = RoundMetrics.nines(holes)
        DashboardCard(title: "Scorecard", subtitle: nines.isEmpty ? "Pull to refresh to load hole scores." : "Circles are under par, boxes over", headline: nil, showsChevron: false) {
            ForEach(Array(nines.enumerated()), id: \.offset) { index, nine in
                NineGrid(holes: nine, totalLabel: nines.count == 2 ? (index == 0 ? "Out" : "In") : "Tot")
            }
            if nines.count == 2 {
                HStack {
                    Text("Total").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Par \(RoundMetrics.total(holes, \.par) ?? 0)").foregroundStyle(.secondary)
                    Text("\(RoundMetrics.total(holes, \.grossScore) ?? 0)").font(Theme.score(.title3)).foregroundStyle(Theme.pine)
                }
            }
        }
    }

    private struct NineGrid: View {
        let holes: [Scorecard.Hole]
        let totalLabel: String

        var body: some View {
            Grid(horizontalSpacing: 0, verticalSpacing: 6) {
                GridRow {
                    rowLabel("Hole")
                    ForEach(holes.indices, id: \.self) { i in cell(holes[i].holeNumber.map { "\($0)" }, bold: true) }
                    cell(totalLabel, bold: true)
                }
                GridRow {
                    rowLabel("Yds")
                    ForEach(holes.indices, id: \.self) { i in
                        cell(holes[i].distance.map { "\(Int(Units.yards(fromMeters: $0).rounded()))" }, small: true)
                    }
                    cell(nil)
                }
                GridRow {
                    rowLabel("Par")
                    ForEach(holes.indices, id: \.self) { i in cell(holes[i].par.map { "\($0)" }) }
                    cell(RoundMetrics.total(holes, \.par).map { "\($0)" })
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    rowLabel("Score")
                    ForEach(holes.indices, id: \.self) { i in ScoreMark(hole: holes[i]) }
                    cell(RoundMetrics.total(holes, \.grossScore).map { "\($0)" }, bold: true)
                }
                GridRow {
                    rowLabel("Putts")
                    ForEach(holes.indices, id: \.self) { i in cell(holes[i].putts.map { "\($0)" }, small: true) }
                    cell(RoundMetrics.total(holes, \.putts).map { "\($0)" }, small: true)
                }
            }
            .padding(.vertical, 6)
        }

        private func rowLabel(_ text: String) -> some View {
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }

        private func cell(_ text: String?, bold: Bool = false, small: Bool = false) -> some View {
            Text(text ?? "")
                .font(small ? .caption2 : (bold ? .footnote.weight(.bold) : .footnote))
                .monospacedDigit()
                .foregroundStyle(small ? Color.secondary : Theme.ink)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private struct ScoreMark: View {
        let hole: Scorecard.Hole

        var body: some View {
            let result = RoundMetrics.result(score: hole.grossScore, par: hole.par)
            Text(hole.grossScore.map { "\($0)" } ?? "–")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)
                .overlay {
                    switch result {
                    case .eagleOrBetter:
                        Circle().strokeBorder(Theme.flag, lineWidth: 1.5).padding(-3)
                            .overlay(Circle().strokeBorder(Theme.flag, lineWidth: 1.5))
                    case .birdie:
                        Circle().strokeBorder(Theme.flag, lineWidth: 1.5)
                    case .bogey:
                        Rectangle().strokeBorder(Theme.ink.opacity(0.5), lineWidth: 1)
                    case .doubleOrWorse:
                        Rectangle().strokeBorder(Theme.ink.opacity(0.5), lineWidth: 1).padding(-3)
                            .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.5), lineWidth: 1))
                    case .par, .none:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
        }
    }
}

/// Everything logged on one day: rounds, practice sessions, and shots by club.
struct DayDetailView: View {
    let day: Date
    @Query private var activities: [StoredActivity]
    @Query private var rounds: [StoredRound]
    @Query private var shots: [StoredShot]

    init(day: Date) {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        self.day = start
        _activities = Query(filter: #Predicate<StoredActivity> { $0.date >= start && $0.date < end }, sort: \StoredActivity.date)
        _rounds = Query(filter: #Predicate<StoredRound> { $0.date >= start && $0.date < end }, sort: \StoredRound.date)
        _shots = Query(filter: #Predicate<StoredShot> { $0.date >= start && $0.date < end }, sort: \StoredShot.date)
    }

    private var sessions: [StoredActivity] { activities.filter { ($0.strokeCount ?? 0) > 0 } }
    private var finishedRounds: [StoredRound] { rounds.filter(\.isFinished) }
    private var swings: Int { HomeMetrics.totalSwings(activities.map(\.sample)) }
    private var clubs: [ClubLine] { ClubMetrics.lines(shots.map(\.sample)) }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(label: "Swings", value: swings.formatted(), detail: "Putting not counted")
                    StatTile(label: "Sessions", value: "\(sessions.count)",
                             detail: finishedRounds.isEmpty ? "No rounds" : "\(finishedRounds.count) \(finishedRounds.count == 1 ? "round" : "rounds")")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if !finishedRounds.isEmpty {
                Section("Rounds") {
                    ForEach(finishedRounds) { round in
                        NavigationLink {
                            RoundDetailView(round: round)
                        } label: {
                            RoundRow(round: round)
                        }
                    }
                }
            }
            if !sessions.isEmpty {
                Section("Practice sessions") {
                    ForEach(sessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Metrics.kindLabel(session.kind ?? session.typename))
                                Text(session.date, format: .dateTime.hour().minute())
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(session.strokeCount ?? 0) shots").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !clubs.isEmpty {
                Section {
                    ForEach(clubs) { line in
                        HStack {
                            Text(ClubMetrics.label(line.club))
                            Spacer()
                            Text("\(line.shots)").monospacedDigit().foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                            Text(Format.yards(line.carryYards) ?? "–").monospacedDigit().frame(width: 64, alignment: .trailing)
                            Text(Format.mph(line.ballSpeedMph) ?? "–").monospacedDigit().foregroundStyle(.secondary).frame(width: 68, alignment: .trailing)
                        }
                    }
                } header: {
                    HStack {
                        Text("Clubs")
                        Spacer()
                        Text("Shots · Carry · Ball speed")
                    }
                } footer: {
                    Text("Averages from practice shots that day.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ground.ignoresSafeArea())
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
