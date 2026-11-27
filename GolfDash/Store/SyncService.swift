import Foundation
import SwiftData
import TrackManKit

/// Pulls new rounds and activities from TrackMan into SwiftData.
@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    /// "Loading shots 3 of 40" while session shots download.
    @Published private(set) var progress: String?
    @Published private(set) var lastSynced: Date? = UserDefaults.standard.object(forKey: SyncService.lastSyncedKey) as? Date

    /// The player's TrackMan handicap from the last successful sync.
    @Published private(set) var handicap: Double? = UserDefaults.standard.object(forKey: SyncService.handicapKey) as? Double

    /// Bump when the shot query gains fields, so old sessions refetch.
    static let shotFieldsVersion = 2

    private static let lastSyncedKey = "lastSynced"
    private static let handicapKey = "trackmanHandicap"

    func sync(session: AppSession, context: ModelContext, fullResync: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let knownRounds = Set(try context.fetch(FetchDescriptor<StoredRound>()).map(\.id))
            let knownActivities = Set(try context.fetch(FetchDescriptor<StoredActivity>()).map(\.id))
            let api = session.api

            // Rounds stored before scorecards were synced need one full pass.
            let missingHoles = try context.fetch(FetchDescriptor<StoredRound>()).contains { $0.holesData == nil }
            let cards = try await Paging.fetchNew(knownIDs: knownRounds, fullResync: fullResync || missingHoles) { skip, take in
                try await api.scorecards(skip: skip, take: take)
            }
            let activities = try await Paging.fetchNew(knownIDs: knownActivities, fullResync: fullResync) { skip, take in
                try await api.activities(skip: skip, take: take)
            }

            try upsert(cards, into: context)
            try upsert(activities, into: context)
            try context.save()
            // The handicap is a bonus: a failure here must not fail the sync.
            if let hcp = try? await api.handicap() {
                handicap = hcp
                UserDefaults.standard.set(hcp, forKey: Self.handicapKey)
            }
            try await fetchShots(api: api, context: context)

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
        try? context.delete(model: StoredShot.self)
        try? context.save()
        lastSynced = nil
        handicap = nil
        UserDefaults.standard.removeObject(forKey: Self.lastSyncedKey)
        UserDefaults.standard.removeObject(forKey: Self.handicapKey)
    }

    /// Downloads shots for practice sessions not fetched yet, newest first,
    /// saving as it goes so an interrupted sync keeps its progress.
    private func fetchShots(api: TrackManAPI, context: ModelContext) async throws {
        defer { progress = nil }
        let pending = try context.fetch(FetchDescriptor<StoredActivity>(sortBy: [SortDescriptor(\StoredActivity.date, order: .reverse)]))
            .filter { (!$0.shotsFetched || $0.shotFieldsVersion < Self.shotFieldsVersion) && ($0.strokeCount ?? 0) > 0 && Metrics.isFullSwing(typename: $0.typename, kind: $0.kind) }
        for (index, activity) in pending.enumerated() {
            progress = "Loading shots, session \(index + 1) of \(pending.count)"
            let strokes: [Stroke]
            do {
                strokes = try await api.strokes(activityID: activity.id)
            } catch let error as AuthError {
                throw error
            } catch {
                continue // Try this session again on the next sync.
            }
            for (number, stroke) in strokes.enumerated() {
                context.insert(StoredShot(activityID: activity.id, index: number, sessionDate: activity.date, stroke: stroke))
            }
            activity.shotsFetched = true
            activity.shotFieldsVersion = Self.shotFieldsVersion
            if index % 10 == 9 { try context.save() }
        }
        try context.save()
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
