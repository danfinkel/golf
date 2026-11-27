import SwiftData
import SwiftUI
import TrackManKit

struct SyncStatusView: View {
    @ObservedObject var sync: SyncService

    var body: some View {
        HStack(spacing: 6) {
            if sync.isSyncing {
                ProgressView().controlSize(.small)
                Text(sync.progress ?? "Syncing with TrackMan…")
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
    var showsChevron = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if let headline {
                    Text(headline).font(Theme.score(.title)).foregroundStyle(Theme.pine)
                }
                if showsChevron {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                }
            }
            content
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

enum Format {
    static func yards(_ value: Double?) -> String? {
        value.map { "\(Int($0.rounded())) yd" }
    }

    static func mph(_ value: Double?) -> String? {
        value.map { "\(Int($0.rounded())) mph" }
    }

    static func handicap(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }

    static func degrees(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))°"
    }

    static func percent(_ share: Double?) -> String? {
        share.map { "\(Int(($0 * 100).rounded()))%" }
    }
}

/// A small labeled number, used in rows of two on Home and Driver.
struct StatTile: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.score(.title))
                .foregroundStyle(Theme.pine)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: Theme.ink.opacity(0.06), radius: 1, y: 1)
    }
}

/// Section heading inside a scroll view.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.display(.title2))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}
