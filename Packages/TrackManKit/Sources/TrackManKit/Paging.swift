import Foundation

public enum Paging {
    /// Fetches newest-first pages until a short page, or (unless `fullResync`)
    /// until a page contains an item already stored. The page with the known
    /// item is still returned so recently edited items get updated.
    public static func fetchNew<Item: Identifiable>(
        pageSize: Int = 50,
        knownIDs: Set<String>,
        fullResync: Bool,
        maxPages: Int = 200,
        fetch: (_ skip: Int, _ take: Int) async throws -> [Item]
    ) async throws -> [Item] where Item.ID == String {
        var collected: [Item] = []
        var skip = 0
        for _ in 0..<maxPages {
            let page = try await fetch(skip, pageSize)
            collected.append(contentsOf: page)
            if page.count < pageSize { break }
            if !fullResync, page.contains(where: { knownIDs.contains($0.id) }) { break }
            skip += page.count
        }
        return collected
    }
}
