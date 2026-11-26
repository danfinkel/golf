import SwiftData
import SwiftUI
import TrackManKit

/// The landing tab: headline numbers, this month's calendar, the latest
/// round and recent swing volume.
struct HomeView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @ObservedObject var sync: SyncService
    @Query(sort: \StoredRound.date) private var rounds: [StoredRound]
    @Query(sort: \StoredActivity.date) private var activities: [StoredActivity]
    @State private var showSettings = false
    @State private var month = Date()

    private var samples: [ActivitySample] { activities.map(\.sample) }
    private var thisMonth: DateInterval? { HomeMetrics.month(containing: Date()) }
    private var swings: [DailySwings] { Metrics.dailySwings(samples, endingAt: Date()) }

    private var monthSwings: Int {
        HomeMetrics.totalSwings(samples, from: thisMonth?.start, to: thisMonth?.end)
    }

    private var practiceDaysThisMonth: Int {
        HomeMetrics.monthLog(containing: Date(), activities: samples, roundDates: []).filter { $0.sessions > 0 }.count
    }

    private var streak: Int {
        let days = Set(samples.filter { ($0.strokeCount ?? 0) > 0 }.map { Calendar.current.startOfDay(for: $0.date) })
            .union(rounds.map { Calendar.current.startOfDay(for: $0.date) })
        return HomeMetrics.streak(activeDays: days, today: Date())
    }

    /// The most recent round that recorded a course handicap.
    private var handicapRound: StoredRound? { rounds.last { $0.courseHandicap != nil } }

    @ViewBuilder private var handicapTile: some View {
        if let hcp = sync.handicap {
            StatTile(label: "Handicap", value: Format.handicap(hcp), detail: "TrackMan handicap")
        } else if let round = handicapRound, let course = round.courseHandicap {
            StatTile(label: "Handicap", value: Format.handicap(course),
                     detail: "Course hcp, \(round.date.formatted(.dateTime.month().day()))")
        } else {
            StatTile(label: "Handicap", value: "–", detail: "Not set in TrackMan")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    SyncStatusView(sync: sync)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        StatTile(label: "Swings this month", value: monthSwings.formatted(),
                                 detail: "\(practiceDaysThisMonth) practice \(practiceDaysThisMonth == 1 ? "day" : "days")")
                        StatTile(label: "All-time swings", value: HomeMetrics.totalSwings(samples).formatted(),
                                 detail: "\(activities.filter { ($0.strokeCount ?? 0) > 0 }.count) sessions")
                        handicapTile
                        StatTile(label: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days")",
                                 detail: "Days in a row on TrackMan")
                    }
                    MonthCalendarCard(month: $month, activities: samples, roundDates: rounds.map(\.date))
                    if let latest = rounds.last {
                        LatestRoundCard(round: latest)
                    }
                    NavigationLink {
                        SwingsDetailView(days: swings)
                    } label: {
                        SwingsCard(days: swings)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle(session.displayName.map { "Hi, \($0)" } ?? "Home")
            .refreshable { await sync.sync(session: session, context: context) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(sync: sync)
            }
        }
    }
}

/// A month grid. Practice days fill green, darker with more swings; round
/// days get a flag-yellow ring.
struct MonthCalendarCard: View {
    @Binding var month: Date
    let activities: [ActivitySample]
    let roundDates: [Date]

    private let calendar = Calendar.current
    private var log: [DayLog] { HomeMetrics.monthLog(containing: month, activities: activities, roundDates: roundDates) }
    private var isCurrentMonth: Bool { calendar.isDate(month, equalTo: Date(), toGranularity: .month) }

    /// Blank cells before the 1st so it lands under its weekday.
    private var leadingBlanks: Int {
        guard let first = log.first?.day else { return 0 }
        return (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        let maxSwings = max(log.map(\.swings).max() ?? 0, 1)
        let active = log.filter(\.isActive).count
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(month, format: .dateTime.month(.wide).year()).font(.headline).foregroundStyle(Theme.ink)
                    Text("\(active) TrackMan \(active == 1 ? "day" : "days")").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(isCurrentMonth)
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(log) { day in
                    DayCell(day: day, intensity: Double(day.swings) / Double(maxSwings),
                            isToday: calendar.isDateInToday(day.day))
                }
            }
            HStack(spacing: 14) {
                Legend(color: Theme.fairway, text: "Practice")
                Legend(color: Theme.flag, text: "Round", ring: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
    }

    private struct DayCell: View {
        let day: DayLog
        let intensity: Double
        let isToday: Bool

        var body: some View {
            let practiced = day.sessions > 0
            Text(day.day, format: .dateTime.day())
                .font(.footnote.weight(practiced ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(practiced && intensity > 0.45 ? Color.white : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(practiced ? Theme.pine.opacity(0.25 + 0.75 * intensity) : Color.clear)
                }
                .overlay {
                    if day.rounds > 0 {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.flag, lineWidth: 2.5)
                    } else if isToday {
                        RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.ink.opacity(0.3), lineWidth: 1)
                    }
                }
                .accessibilityLabel(accessibility)
        }

        private var accessibility: String {
            var parts = [day.day.formatted(.dateTime.month().day())]
            if day.swings > 0 { parts.append("\(day.swings) swings") }
            if day.rounds > 0 { parts.append("round played") }
            return parts.joined(separator: ", ")
        }
    }

    private struct Legend: View {
        let color: Color
        let text: String
        var ring = false

        var body: some View {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(ring ? Color.clear : color)
                    .overlay { if ring { RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 2) } }
                    .frame(width: 12, height: 12)
                Text(text)
            }
        }
    }
}

struct LatestRoundCard: View {
    let round: StoredRound

    private var score: String {
        guard let gross = round.grossScore else { return "–" }
        guard let toPar = round.toPar else { return "\(gross)" }
        return "\(gross) (\(toPar == 0 ? "E" : toPar > 0 ? "+\(toPar)" : "\(toPar)"))"
    }

    var body: some View {
        DashboardCard(
            title: "Latest round",
            subtitle: [round.courseName, round.date.formatted(.dateTime.month().day()), round.holesPlayed.map { "\($0) holes" }]
                .compactMap { $0 }.joined(separator: " · "),
            headline: score,
            showsChevron: false
        ) {
            HStack {
                miniStat("Putts", round.putts.map { "\($0)" })
                miniStat("Fairways", fairways)
                miniStat("Greens", round.greensInRegulation.map { "\($0)" })
                miniStat("Drive", Format.yards(round.driveAverageMeters.map(Units.yards(fromMeters:))))
            }
        }
    }

    private var fairways: String? {
        guard let hit = round.fairwaysHit else { return nil }
        let total = hit + (round.fairwaysLeft ?? 0) + (round.fairwaysRight ?? 0)
        return total > 0 ? "\(hit)/\(total)" : nil
    }

    private func miniStat(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value ?? "–").font(Theme.score(.title3)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
