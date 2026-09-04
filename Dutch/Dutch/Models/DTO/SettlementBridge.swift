/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit

/// Maps Core Data objects onto the storage-independent value types in
/// `DutchKit`. Keeping the conversion in one place means the settlement maths
/// never has to know that Core Data exists, and stays testable without a stack.

extension Person {
    /// `nil` when the record is incomplete — CloudKit requires every attribute
    /// to be optional, so a partially synced record is representable.
    var participant: Participant? {
        guard let id, let name else { return nil }
        return Participant(id: id, name: name)
    }
}

extension Expense {
    /// `nil` when the expense has no id or no payer, in which case it cannot
    /// contribute to a balance.
    ///
    /// Reimbursements map through here exactly like any other expense. A
    /// payment from one member to another *is* an expense paid by the debtor
    /// and shared by the creditor alone, so the calculator needs no notion of
    /// settling — see `GroupStore.recordPayment`.
    var entry: ExpenseEntry? {
        guard let id, let payerID = paidBy?.id else { return nil }

        let sharers = (splitAmong as? Set<Person>)?.compactMap(\.id) ?? []
        let weights = shareWeights

        return ExpenseEntry(
            id: id,
            amount: Money(amount: amount),
            payer: payerID,
            // Uniqued rather than trapping: two half-synced `Person` records
            // can carry the same id, and `Dictionary(uniqueKeysWithValues:)`
            // would abort the app rather than render a slightly stale split.
            shares: Dictionary(
                sharers.map { ($0, weights[$0] ?? 1) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}

// MARK: - Share Weights

extension Expense {
    /// How the cost divides, as a weight per member — two shares for the couple
    /// in the double room, one for whoever is in the single.
    ///
    /// An overlay, not the source of truth: `splitAmong` still decides *who* is
    /// in the split, and this only says how much each of them takes. A member
    /// with no entry here weighs `1`, so an expense saved before this existed —
    /// or any ordinary even split — reads exactly as it always did.
    ///
    /// Stored as JSON in a string attribute rather than as its own entity. A
    /// join entity would be the textbook shape, but it triples the record count
    /// for a feature most expenses never use, and every one of those records
    /// would sync separately.
    var shareWeights: [UUID: Int] {
        guard
            let json = shareWeightsJSON?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: json)
        else { return [:] }

        return Dictionary(
            decoded.compactMap { key, weight in UUID(uuidString: key).map { ($0, weight) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Records a weighting, or clears it when the split is even.
    ///
    /// An even split writes `nil` rather than a dictionary of `1`s. That keeps
    /// the ordinary expense byte-identical to what it was before this feature
    /// existed, which matters most for the client that hasn't updated yet: it
    /// sees a plain even split, because that is exactly what it is.
    func setShareWeights(_ weights: [UUID: Int]?, exact: Set<UUID> = []) {
        // More than one distinct weight, or there is nothing to record: a
        // uniform weighting is an even split however large the number is, and
        // a single sharer takes the whole amount either way.
        //
        // This applies to exact amounts too, and correctly: three people who
        // each turned out to owe exactly 10.00 of a 30.00 bill *are* an even
        // split, and storing it as one keeps the record identical to what it
        // would have been had nobody itemised. The cost is only that reopening
        // it shows an even split rather than three typed figures — the money is
        // unchanged, which is the part that has to survive.
        guard let weights, Set(weights.values).count > 1 else {
            shareWeightsJSON = nil
            return
        }

        var encodable = Dictionary(
            weights.map { ($0.key.uuidString, $0.value) },
            uniquingKeysWith: { first, _ in first }
        )

        // Only for members who actually have a weight, so a marker can't
        // outlive the row it describes.
        for id in exact where weights[id] != nil {
            encodable[Self.exactMarkerPrefix + id.uuidString] = 1
        }

        shareWeightsJSON = (try? JSONEncoder().encode(encodable))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    /// The members whose weight was typed as a cash figure rather than as a
    /// percentage.
    ///
    /// Presentation only. Nothing about the split depends on it — the weights
    /// alone decide every cent — and a record whose markers were lost entirely
    /// still divides exactly as it should. It exists so that reopening an
    /// itemised bill shows the figures that were typed instead of the cent
    /// counts they became, which would read as `2350%`.
    ///
    /// **Why this is not a new attribute.** The markers ride in the same JSON
    /// under keys that are deliberately not UUIDs, and `shareWeights` above
    /// already discards any key that fails `UUID(uuidString:)`. So a build that
    /// has never heard of exact amounts — including every copy already
    /// installed — reads the weighting correctly and ignores these completely.
    /// A new attribute would have meant a model version, a lightweight
    /// migration and the CloudKit initialize-and-promote dance, all to carry a
    /// hint that changes no balance anywhere.
    var exactShareIDs: Set<UUID> {
        guard
            let json = shareWeightsJSON?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: json)
        else { return [] }

        return Set(
            decoded.keys.compactMap { key in
                guard key.hasPrefix(Self.exactMarkerPrefix) else { return nil }
                return UUID(uuidString: String(key.dropFirst(Self.exactMarkerPrefix.count)))
            }
        )
    }

    /// Leads with `$` so the key can never be mistaken for a UUID, which is
    /// what keeps an older client's decoder throwing it away rather than
    /// treating it as a member.
    private static let exactMarkerPrefix = "$exact."
}

extension ExpenseGroup {
    /// Every member that is complete enough to take part in a split.
    var roster: [Participant] {
        (members as? Set<Person>)?
            .compactMap(\.participant)
            .sorted { $0.name < $1.name } ?? []
    }

    /// Every expense on the group, payments included.
    var expenseSet: Set<Expense> { (expenses as? Set<Expense>) ?? [] }

    /// What people actually bought, with the payments settling up left out.
    var spending: [Expense] { expenseSet.filter { !$0.isReimbursement } }

    var entries: [ExpenseEntry] {
        expenseSet.compactMap(\.entry)
    }

    /// Net position per member, including members who come out even.
    var balances: [Balance] {
        SettlementCalculator.balances(for: entries, roster: roster)
    }

    /// The payments that would settle the group.
    var transfers: [Transfer] {
        SettlementCalculator.transfers(settling: balances)
    }

    /// Everything the group has spent, whoever paid for it.
    ///
    /// Reimbursements are excluded. Paying back what you owe moves money
    /// between two people but buys nothing, and counting it here would inflate
    /// the trip's total every time somebody settled up.
    var totalSpent: Money {
        spending.compactMap(\.entry).reduce(Money.zero) { $0 + $1.amount }
    }

    /// True when nobody owes anybody — including a group with no expenses yet.
    var isSettled: Bool {
        balances.allSatisfy(\.amount.isZero)
    }
}

// MARK: - Composite

extension ExpenseGroup {
    /// Everything a screen derives from a group's contents, from one pass.
    ///
    /// Each accessor above is honest on its own but rebuilds `entries` and
    /// `roster` from the relationship sets, and `transfers` runs `balances`
    /// again on top of that. Reading several of them — which every screen in
    /// the app does — pays for that walk once per reading, and reading one
    /// *per row* pays for it once per row.
    struct Settlement {
        let transfers: [Transfer]
        let totalSpent: Money

        /// How many of the group's expenses are actual spending, for the screen
        /// that reports a count next to the total. Counting the rows instead
        /// would say "12 expenses" over a total that only added up nine of them.
        let spendingCount: Int

        /// Net position keyed by participant, because the screens that show a
        /// balance show one per member row. Scanning the ordered `balances`
        /// array per row is quadratic in members; the ordered form is still on
        /// the group itself for anyone who wants it.
        let balanceByParticipant: [Participant.ID: Money]
    }

    /// Computes the group's settlement in a single pass over its members and
    /// expenses, as read off the relationships.
    ///
    /// A method rather than a property, deliberately: this is not free, and a
    /// call site should read like it costs something. Take one per render and
    /// pass it down — don't call it per row.
    ///
    /// Screens should prefer `settlement(members:expenses:)` with fetched
    /// results. The relationship sets are a snapshot that SwiftUI has no way to
    /// observe, so a view built on this one goes stale the moment somebody
    /// edits an expense — see `Person.request(in:)`.
    func settlement() -> Settlement {
        settlement(
            members: Array((members as? Set<Person>) ?? []),
            expenses: Array(expenseSet)
        )
    }

    /// The same computation over members and expenses the caller already holds,
    /// so a view can drive it from `@FetchRequest` rather than from the
    /// relationship sets.
    ///
    /// Order of the arguments doesn't matter: the roster is sorted here, which
    /// is what keeps the greedy transfer list stable between call sites.
    func settlement(members: [Person], expenses: [Expense]) -> Settlement {
        let roster = members
            .compactMap(\.participant)
            .sorted { $0.name < $1.name }

        // One walk for both answers. Every expense feeds the balances —
        // payments included, since they are what clears a debt — while only
        // real spending adds to the total.
        var entries: [ExpenseEntry] = []
        var totalSpent = Money.zero
        var spendingCount = 0

        for expense in expenses {
            guard let entry = expense.entry else { continue }
            entries.append(entry)
            guard !expense.isReimbursement else { continue }
            totalSpent += entry.amount
            spendingCount += 1
        }

        let balances = SettlementCalculator.balances(for: entries, roster: roster)

        return Settlement(
            transfers: SettlementCalculator.transfers(settling: balances),
            totalSpent: totalSpent,
            spendingCount: spendingCount,
            balanceByParticipant: Dictionary(
                balances.map { ($0.participant.id, $0.amount) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}

// MARK: - Currency

extension ExpenseGroup {
    /// The currency every amount in this group is expressed in.
    ///
    /// Stored on the group rather than read from `Locale.current` at display
    /// time. A group shared between someone in Kraków and someone in Berlin is
    /// still one bill in one currency, and rendering the same cents as `zł` on
    /// one device and `€` on the other would be quietly, unfixably wrong.
    ///
    /// Optional in the model because CloudKit requires it, so groups created
    /// before this attribute existed fall back to the reader's own locale.
    var currency: String {
        currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }
}

extension Money {
    /// Formats in the currency the given group is denominated in.
    func formatted(in group: ExpenseGroup) -> String {
        formatted(currencyCode: group.currency)
    }
}

// MARK: - Sharing

extension ExpenseGroup {
    /// A shareable snapshot of where the group stands.
    ///
    /// Takes the settlement and the sorted expenses the caller already holds
    /// rather than recomputing them. `settlement()` is a full walk of the
    /// group, and the only screen that offers to share has done it once this
    /// render already — see `GroupDetailView.Contents`.
    ///
    /// What comes back contains no managed objects, only DutchKit values. That
    /// is what makes it safe to hand to `ShareLink` and render into text later,
    /// on whatever actor the share sheet gets around to calling on, instead of
    /// rebuilding the whole message on every redraw of the screen behind it.
    func summary(
        from settlement: Settlement,
        expenses: [Expense],
        memberCount: Int
    ) -> GroupSummary {
        GroupSummary(
            name: name ?? "",
            currencyCode: currency,
            totalSpent: settlement.totalSpent,
            spendingCount: settlement.spendingCount,
            memberCount: memberCount,
            transfers: settlement.transfers,
            entries: expenses.compactMap(\.summaryLine)
        )
    }
}

extension Expense {
    /// What was handed over at the till, when that wasn't the group's currency.
    ///
    /// Purely provenance for display. `amount` was converted once when the
    /// expense was saved and is the only figure the settlement ever reads —
    /// nothing here is used to recompute it, which is what stops a group's
    /// balances from drifting as rates move. See `ForeignAmount`.
    ///
    /// `originalCurrencyCode` is the discriminator: the two `Double`s are
    /// scalar attributes that read back as `0` when absent, so they cannot say
    /// on their own whether an expense was ever converted. Records written
    /// before this existed, and those paid in the group's own currency, return
    /// `nil` here and render exactly as they always did.
    var foreignAmount: ForeignAmount? {
        guard let code = originalCurrencyCode else { return nil }
        return ForeignAmount(amount: originalAmount, currencyCode: code, rate: exchangeRate)
    }

    /// This expense as one line of a shared summary.
    ///
    /// `nil` when the record cannot describe itself — the same incompleteness
    /// that keeps a half-synced expense out of `entry`. A line reading "paid by
    /// ?" is worse than no line at all here: the whole point of pasting the log
    /// into the group chat is that the others can check it against what they
    /// remember paying.
    var summaryLine: GroupSummary.Entry? {
        guard let payer = paidBy?.name else { return nil }

        // A payment with no recipient would fall through the `paidBackTo`
        // discriminator and render as an ordinary purchase — of nothing, by
        // someone, for the amount that actually settled a debt.
        let recipient = reimbursementRecipient?.name
        if isReimbursement, recipient == nil { return nil }

        return GroupSummary.Entry(
            title: title ?? "",
            amount: Money(amount: amount),
            payer: payer,
            date: date,
            foreign: foreignAmount,
            paidBackTo: recipient
        )
    }

    /// Who a payment went to, for the row that renders "Bob paid Anna".
    ///
    /// A reimbursement is stored with exactly one member in `splitAmong` — the
    /// person being paid back — so this is that member. `nil` for ordinary
    /// expenses, which is what makes it usable as the discriminator in a view.
    var reimbursementRecipient: Person? {
        guard isReimbursement else { return nil }
        return (splitAmong as? Set<Person>)?.first
    }
}
