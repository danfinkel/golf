import SwiftData
import SwiftUI
import TrackManKit

struct DashboardView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @StateObject private var sync = SyncService()
    @Query(sort: \StoredRound.date) private var rounds: [StoredRound]
    @Query(sort: \StoredActivity.date) private var activities: [StoredActivity]
    @State private var showSettings = false

    private var trend: [DrivePoint] { Metrics.driveTrend(rounds.map(\.sample)) }
    private var swings: [DailySwings] { Metrics.dailySwings(activities.map(\.sample), endingAt: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SyncStatusView(sync: sync)
                    NavigationLink {
                        DriveDetailView(rounds: rounds)
                    } label: {
                        DriveCard(points: trend)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        SwingsDetailView(days: swings)
                    } label: {
                        SwingsCard(days: swings)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle(session.displayName.map { "Hi, \($0)" } ?? "Overview")
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
            .task {
                let stale = sync.lastSynced.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
                if stale || rounds.isEmpty {
                    await sync.sync(session: session, context: context)
                }
            }
        }
    }
}

struct SyncStatusView: View {
    @ObservedObject var sync: SyncService

    var body: some View {
        HStack(spacing: 6) {
            if sync.isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing with TrackMan…")
            } else if let error = sync.lastError {
                Image(systemName: "exclamationmark.triangle")
                Text(error)
            } else if let last = sync.lastSynced {
                Text("Updated \(last, format: .relative(presentation: .named))")
            } else {
                Text("Pull to refresh")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(sync.lastError == nil ? Color.secondary : Color.orange)
    }
}

/// Shared card chrome: title, subtitle, headline number, then content.
struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String
    let headline: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let headline {
                    Text(headline).font(.title2.bold()).monospacedDigit()
                }
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
            }
            content
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

enum Format {
    static func yards(_ value: Double?) -> String? {
        value.map { "\(Int($0.rounded())) yd" }
    }
}
