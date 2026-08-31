/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit

/// Write operations on groups.
///
/// Reads deliberately live in `@FetchRequest` instead of here. A hand-rolled
/// fetch into an array only refreshes when something calls it again, so changes
/// arriving from CloudKit would never reach the UI — which is most of the point
/// of this app.
struct GroupStore {
    let context: NSManagedObjectContext

    @discardableResult
    func createGroup(
        named name: String,
        currencyCode: String? = nil,
        appearance: GroupAppearance? = nil
    ) throws -> ExpenseGroup {
        let group = ExpenseGroup(context: context)
        group.id = UUID()
        group.name = name
        group.wordSequence = WordGenerator.generate()
        group.creationDate = Date()
        // Pinned at creation so the group reads the same on every member's
        // device, whatever locale they happen to be in.
        group.currencyCode = currencyCode ?? Locale.current.currency?.identifier ?? "USD"
        // Left unset when nobody chose, so the group falls back to the look
        // derived from its id rather than to a stored default that every group
        // created this way would share. See `ExpenseGroup.appearance`.
        group.symbolName = appearance?.symbol.rawValue
        group.colorName = appearance?.color.rawValue

        try context.save()
        return group
    }

    /// Renames a group and restyles it.
    ///
    /// Both sync, deliberately: a group's name and its icon are what it *is* to
    /// everyone on the trip, not a preference of whoever happens to be looking.
    /// The currency is absent for the opposite reason — it was pinned at
    /// creation, and changing it later would reinterpret every amount already
    /// recorded as if it had been paid in the new one.
    func update(_ group: ExpenseGroup, name: String, appearance: GroupAppearance) throws {
        group.name = name
        group.symbolName = appearance.symbol.rawValue
        group.colorName = appearance.color.rawValue

        try context.save()
    }

    @discardableResult
    func addMember(named name: String, to group: ExpenseGroup) throws -> Person {
        let person = Person(context: context)
        person.id = UUID()
        person.name = name
        person.group = group

        try context.save()
        return person
    }

    /// Renames a member and sets the colour of their circle, or with a `nil`
    /// colour hands them back to the roster's automatic assignment.
    ///
    /// Both in one call, like `update(_ group:name:appearance:)` above, because
    /// both are facts about who this person *is* to everyone on the trip rather
    /// than preferences of whoever happens to be looking — and because the sheet
    /// that calls this can change either.
    ///
    /// Unset is a real state and not a default — see `Person.chosenColor` — so
    /// clearing the colour restores the derived one rather than freezing today's
    /// answer as a stored value that happens to match.
    ///
    /// Renaming is the whole reason this exists. Until it did, a name typed
    /// wrong at a dinner table was permanent, and it was permanent on everyone
    /// else's phone too.
    func update(_ member: Person, name: String, color: PaletteColor?) throws {
        member.name = name
        member.chosenColor = color
        try context.save()
    }

    /// Records that a member is this device's iCloud account, or with `nil`
    /// gives up the claim.
    ///
    /// Only ever writes *this* device's own account — there is no path here for
    /// saying who somebody else is. That is not a simplification: the owner
    /// deciding that a given Apple ID is "Bartek" is a guess, and a guess that
    /// syncs to everyone and renames their identity. Each person claiming their
    /// own row is self-correcting, and the only version where the claim is
    /// evidence rather than an assumption.
    ///
    /// The claim is released from any member who held it first, so a correction
    /// moves the link rather than leaving the same Apple ID on two rows and
    /// making `ExpenseDefaults.me` pick whichever the roster sorted first.
    func claim(_ person: Person?, in group: ExpenseGroup) throws {
        guard let recordName = CloudIdentity.current else { return }

        for member in (group.members as? Set<Person>) ?? []
        where member.cloudUserRecordName == recordName {
            member.cloudUserRecordName = nil
        }
        person?.cloudUserRecordName = recordName

        try context.save()
    }

    /// Deletes a group along with its members and expenses, via the model's
    /// cascade rules.
    func delete(_ group: ExpenseGroup) throws {
        // Before the delete, not after: once the context has saved, `group` is
        // an invalidated object and reading `id` off it to build the key is no
        // longer safe. If the save then fails, the cost is a forgotten default
        // that the next saved expense sets again.
        ExpenseDefaults.forget(group)
        context.delete(group)
        try context.save()
    }

    func delete(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    /// Removes a member, along with every expense they paid for.
    ///
    /// The model nullifies `paidBy` on delete, which would leave those expenses
    /// payer-less. `Expense.entry` then drops them, so the money would vanish
    /// from the split without ever appearing as a deletion — the balances would
    /// simply be wrong. Removing them outright is the honest behaviour, and the
    /// UI warns before calling this.
    func delete(_ member: Person) throws {
        for case let expense as Expense in member.paidExpenses ?? [] {
            context.delete(expense)
        }
        context.delete(member)
        try context.save()
    }

    /// Records an expense, optionally noting that it was paid in another
    /// currency.
    ///
    /// `foreign` is provenance only, and the conversion is not done here: pass
    /// `foreign.converted` as `amount` so the rounding happens once, at the
    /// point the user confirmed the figure they saw. `amount` is always in the
    /// group's own currency, which is what keeps the settlement single-currency
    /// and `SettlementBridge` unaware that any of this exists.
    ///
    /// `date` defaults to now, so the intents and `ScreenshotSeed` — which have
    /// no field to ask with — are unchanged. It is non-optional on purpose:
    /// the day grouping gives a dateless record its own `.distantPast` bucket
    /// at the bottom of the log, and that bucket exists for a record caught
    /// mid-sync, never for something a user chose.
    func addExpense(
        title: String,
        amount: Money,
        paidBy payer: Person,
        splitAmong participants: Set<Person>,
        in group: ExpenseGroup,
        on date: Date = Date(),
        paidIn foreign: ForeignAmount? = nil,
        shares: [UUID: Int]? = nil
    ) throws {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.date = date
        expense.group = group

        apply(
            title: title,
            amount: amount,
            paidBy: payer,
            splitAmong: participants,
            foreign: foreign,
            shares: shares,
            to: expense
        )

        try context.save()
    }

    /// Rewrites an existing expense in place.
    ///
    /// The alternative — delete and re-add — is what the UI used to force, and
    /// on a shared group it means everyone else watches the expense disappear
    /// and come back as something else. Editing keeps one record with one
    /// identity, so CloudKit sends a modification and the other devices just
    /// see the corrected figure.
    ///
    /// `date` used to be deliberately untouched here, on the grounds that an
    /// edit corrects what was recorded rather than moving the expense to today.
    /// That was written when nothing could *state* a date, so the only thing an
    /// edit could do to one was reset it silently — which is what the old rule
    /// protected against. Now that the form carries the field, a wrong date is
    /// exactly what somebody reopens an expense to fix.
    ///
    /// The invariant that survives is the one that mattered: an edit never
    /// moves the date *implicitly*. The form seeds the picker from the stored
    /// value, so passing it back unchanged is a no-op, and only a deliberate
    /// change writes a different day.
    ///
    /// Optional so a caller with no date field — an intent, a future screen —
    /// keeps the old behaviour of leaving it alone rather than silently
    /// stamping today, which is the one failure the original comment named.
    func update(
        _ expense: Expense,
        title: String,
        amount: Money,
        paidBy payer: Person,
        splitAmong participants: Set<Person>,
        on date: Date? = nil,
        paidIn foreign: ForeignAmount? = nil,
        shares: [UUID: Int]? = nil
    ) throws {
        if let date { expense.date = date }

        apply(
            title: title,
            amount: amount,
            paidBy: payer,
            splitAmong: participants,
            foreign: foreign,
            shares: shares,
            to: expense
        )

        try context.save()
    }

    /// Records that one member handed money to another.
    ///
    /// Stored as an ordinary expense — paid by the person settling up, shared
    /// by the person being paid — because that is precisely what a payment is
    /// in balance terms: it credits the payer and debits the recipient by the
    /// same amount, which is exactly what clears a debt between them. The
    /// settlement maths therefore needs no concept of a payment at all.
    ///
    /// `isReimbursement` exists only so the screens can tell the two apart: a
    /// payment is not spending, and must not inflate the group's total.
    ///
    /// `date` defaults to now, and the sheet offers it for the same reason the
    /// expense form does: *"I paid her back last Tuesday"* is as ordinary a
    /// sentence as backdating a receipt, and a payment logged today when it
    /// happened on Tuesday lands in the wrong day of the same log.
    func recordPayment(
        from payer: Person,
        to recipient: Person,
        amount: Money,
        in group: ExpenseGroup,
        on date: Date = Date()
    ) throws {
        let payment = Expense(context: context)
        payment.id = UUID()
        payment.date = date
        payment.group = group
        payment.isReimbursement = true
        // Carried so a client still on the old model — which knows nothing
        // about the flag — shows a labelled expense rather than an untitled
        // one. The balances it computes are right either way.
        payment.title = "Settle up"
        payment.amount = amount.amount
        payment.paidBy = payer
        payment.splitAmong = NSSet(object: recipient)

        try context.save()
    }

    /// The fields `addExpense` and `update` write identically, in one place so
    /// the two cannot drift — an edit that forgot to clear `exchangeRate` would
    /// leave an expense claiming a conversion that no longer applies.
    private func apply(
        title: String,
        amount: Money,
        paidBy payer: Person,
        splitAmong participants: Set<Person>,
        foreign: ForeignAmount?,
        shares: [UUID: Int]?,
        to expense: Expense
    ) {
        // Stored as `nil` when blank rather than as `""`, because a title is
        // optional at the form and every screen already falls back on a
        // *missing* one. An empty string is not missing: it satisfies
        // `title ?? "Untitled"` and draws a blank line where the fallback
        // belongs, which is the one way an untitled expense could look broken
        // rather than merely brief.
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.title = named.isEmpty ? nil : named
        expense.amount = amount.amount
        expense.paidBy = payer
        expense.splitAmong = NSSet(set: participants)

        // Cleared, not just overwritten: an expense edited back into the
        // group's own currency has no original amount any more, and leaving the
        // code behind would keep rendering a foreign receipt under it forever.
        expense.originalAmount = foreign?.amount ?? 0
        expense.originalCurrencyCode = foreign?.currencyCode
        expense.exchangeRate = foreign?.rate ?? 0

        // Weights only for members still in the split, so removing someone from
        // an expense doesn't leave their share behind to be resurrected if they
        // are added back.
        let participantIDs = Set(participants.compactMap(\.id))
        expense.setShareWeights(shares?.filter { participantIDs.contains($0.key) })
    }
}
