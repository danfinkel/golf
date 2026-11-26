import Foundation
import SwiftData
import TrackManKit

/// Pulls new rounds and activities from TrackMan into SwiftData.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSynced: Date? = UserDefaults.standard.object(forKey: SyncService.lastSyncedKey) as? Date

    private static let lastSyncedKey = "lastSynced"

    func sync(session: AppSession, context: ModelContext, fullResync: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let knownRounds = Set(try context.fetch(FetchDescriptor<StoredRound>()).map(\.id))
            let knownActivities = Set(try context.fetch(FetchDescriptor<StoredActivity>()).map(\.id))
            let api = session.api

            let cards = try await Paging.fetchNew(knownIDs: knownRounds, fullResync: fullResync) { skip, take in
                try await api.scorecards(skip: skip, take: take)
            }
            let activities = try await Paging.fetchNew(knownIDs: knownActivities, fullResync: fullResync) { skip, take in
                try await api.activities(skip: skip, take: take)
            }

            try upsert(cards, into: context)
            try upsert(activities, into: context)
            try context.save()

            let now = Date()
            lastSynced = now
            UserDefaults.standard.set(now, forKey: Self.lastSyncedKey)
        } catch {
            lastError = error.localizedDescription
            await session.handle(error)
        }
    }

    func clearCache(context: ModelContext) {
        try? context.delete(model: StoredRound.self)
        try? context.delete(model: StoredActivity.self)
        try? context.save()
        lastSynced = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
    }

    private func upsert(_ cards: [Scorecard], into context: ModelContext) throws {
        var existing = Dictionary(try context.fetch(FetchDescriptor<StoredRound>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for card in cards {
            guard let date = card.date else { continue }
            let round = existing[card.id] ?? {
                let created = StoredRound(id: card.id, date: date)
                context.insert(created)
                return created
            }()
            existing[card.id] = round
            round.update(from: card, date: date)
        }
    }

    private func upsert(_ activities: [Activity], into context: ModelContext) throws {
        var existing = Dictionary(try context.fetch(FetchDescriptor<StoredActivity>()).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for activity in activities {
            guard let date = activity.date else { continue }
            let stored = existing[activity.id] ?? {
                let created = StoredActivity(id: activity.id, typename: activity.typename, date: date)
                context.insert(created)
                return created
            }()
            existing[activity.id] = stored
            stored.update(from: activity, date: date)
        }
    }
}
