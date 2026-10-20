import Foundation
import SwiftData

/// How recent a row is, for choosing between duplicates.
///
/// Two rows of equal freshness are ones nothing can tell apart, which is
/// deliberately not a tie to be broken — see `ModelContext.collapseDuplicates`.
/// A model with no `createdAt` passes its `updatedAt` twice.
struct Freshness: Comparable {
    let updatedAt: Date
    let createdAt: Date

    static func < (a: Self, b: Self) -> Bool {
        a.updatedAt == b.updatedAt ? a.createdAt < b.createdAt : a.updatedAt < b.updatedAt
    }
}

extension ModelContext {
    /// Groups rows by what makes them the same thing, keeps the freshest, and
    /// deletes the rest. Returns the survivors, and the identity of every
    /// group that lost a row so a caller can repair what depended on it.
    ///
    /// One implementation for every repository, because the tie rule below is
    /// the part that must never differ between them.
    ///
    /// Two properties this has to have, and neither is incidental.
    ///
    /// **Every survivor is chosen before anything is deleted.** Reading a
    /// property off a model that has been deleted and saved is undefined, so
    /// the grouping cannot happen afterwards — it would be doing exactly that
    /// to every row it just removed.
    ///
    /// **Rows nothing can tell apart are all kept.** Breaking that tie
    /// arbitrarily is the one genuinely dangerous thing this function could
    /// do: two devices picking differently would each delete what the other
    /// kept, both deletions would sync, and the day would be gone. Keeping
    /// both leaves a duplicate, which is untidy and self-healing — the next
    /// edit stamps one of them and it wins outright from then on. In practice
    /// the tie needs two devices to agree to sub-millisecond precision on both
    /// timestamps, so it is the unreachable branch that matters rather than
    /// the reachable one. The persistent identifier is no tie-breaker either:
    /// each device's store assigns its own, so two devices would not agree.
    func collapseDuplicates<Model: PersistentModel, Key: Hashable, Rank: Comparable>(
        _ models: [Model],
        by key: KeyPath<Model, Key>,
        freshness: (Model) -> Rank
    ) -> (kept: [Model], removed: [Key]) {
        var groups: [Key: [Model]] = [:]
        var order: [Key] = []
        for model in models {
            let identity = model[keyPath: key]
            if groups[identity] == nil { order.append(identity) }
            groups[identity, default: []].append(model)
        }
        guard groups.contains(where: { $0.value.count > 1 }) else { return (models, []) }

        var kept: [Model] = []
        var doomed: [Model] = []
        var removed: [Key] = []
        for identity in order {
            let group = groups[identity] ?? []
            guard group.count > 1 else {
                kept.append(contentsOf: group)
                continue
            }
            let best = group.map(freshness).max()
            let before = doomed.count
            for model in group {
                if freshness(model) == best { kept.append(model) } else { doomed.append(model) }
            }
            if doomed.count > before { removed.append(identity) }
        }

        for loser in doomed { delete(loser) }
        // Saved at once, as every repository write is, so a crash cannot
        // bring the losers back.
        if hasChanges { try? save() }
        // Returned in the order they arrived, which is the order the fetch
        // sorted them into.
        return (kept, removed)
    }
}
