/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit
import Testing
@testable import Dutch

/// End-to-end tests over a real (in-memory) Core Data stack: create a group,
/// add members and expenses, and confirm the balances the UI would render.
///
/// These cover the seam that the pure `DutchKit` tests cannot — that the
/// Core Data objects map onto the value types correctly.
@MainActor
@Suite("GroupStore")
struct GroupStoreTests {

    /// A UUID whose sort position is its leading byte.
    ///
    /// For the one thing in the settlement that depends on the order ids happen
    /// to fall in: when several sharers tie on the same fractional remainder,
    /// `Money.split(among:)` hands the leftover minor units to the earliest
    /// positions, and `SettlementCalculator.precedes` decides those by comparing
    /// the uuid's bytes. A test that wants to know *which* sharer gets the extra
    /// cent has to say what the order is instead of drawing it at random.
    private static func orderedID(_ order: UInt8) -> UUID {
        UUID(uuid: (order, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    }

    // MARK: - Creating

    @Test("Creating a group assigns an id, date and word sequence")
    func createGroup() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")

        #expect(group.name == "Berlin Trip")
        #expect(group.id != nil)
        #expect(group.creationDate != nil)

        let sequence = try #require(group.wordSequence)
        #expect(WordGenerator.isWellFormed(sequence))
    }

    @Test("Members attach to their group")
    func addMembers() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")

        try store.addMember(named: "Alice", to: group)
        try store.addMember(named: "Bob", to: group)

        #expect(group.members?.count == 2)
        #expect(group.roster.map(\.name) == ["Alice", "Bob"])
    }

    @Test("Deleting a group cascades to its members and expenses")
    func deleteCascades() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        try store.addExpense(
            title: "Dinner",
            amount: Money(cents: 1000),
            paidBy: alice,
            splitAmong: [alice],
            in: group
        )

        try store.delete(group)

        #expect(try context.count(for: ExpenseGroup.fetchRequest()) == 0)
        #expect(try context.count(for: Person.fetchRequest()) == 0)
        #expect(try context.count(for: Expense.fetchRequest()) == 0)
    }

    @Test("A new group records the currency it was created in")
    func createGroupPinsCurrency() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip", currencyCode: "EUR")

        #expect(group.currencyCode == "EUR")
        #expect(group.currency == "EUR")
    }

    /// Groups that predate the attribute fall back to the reader's locale
    /// rather than rendering nothing.
    @Test("A group with no stored currency falls back to the locale")
    func currencyFallsBack() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        group.currencyCode = nil

        #expect(group.currency == (Locale.current.currency?.identifier ?? "USD"))
    }

    // MARK: - Deleting

    @Test("Deleting an expense removes it from the balances")
    func deleteExpense() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)

        try store.delete(expense)

        #expect(try context.count(for: Expense.fetchRequest()) == 0)
        #expect(group.isSettled)
        #expect(group.totalSpent == .zero)
    }

    /// The model nullifies `paidBy`, which would leave a payer-less expense
    /// that `Expense.entry` silently drops — the money would vanish from the
    /// split without ever appearing as a deletion.
    @Test("Deleting a member also deletes the expenses they paid for")
    func deleteMemberRemovesTheirExpenses() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )
        try store.addExpense(
            title: "Taxi",
            amount: Money(amount: 10.00),
            paidBy: bob,
            splitAmong: [alice, bob],
            in: group
        )

        try store.delete(alice)

        // Alice's dinner is gone; Bob's taxi survives.
        #expect(try context.count(for: Expense.fetchRequest()) == 1)
        #expect(group.totalSpent == Money(cents: 1000))

        // Bob paid 10.00 and is now the only member, so nobody owes anybody.
        #expect(group.roster.map(\.name) == ["Bob"])
        #expect(group.isSettled)
    }

    // MARK: - Derived summaries

    @Test("Total spent adds up every expense regardless of who paid")
    func totalSpent() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        try store.addExpense(
            title: "Taxi", amount: Money(amount: 12.50),
            paidBy: bob, splitAmong: [alice, bob], in: group
        )

        #expect(group.totalSpent == Money(cents: 4250))
        #expect(!group.isSettled)
    }

    @Test("A group with no expenses reads as settled")
    func emptyGroupIsSettled() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        try store.addMember(named: "Alice", to: group)

        #expect(group.isSettled)
        #expect(group.totalSpent == .zero)
    }

    // MARK: - Balances through the bridge

    @Test("A split expense produces the balances the detail screen shows")
    func balancesAfterExpense() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )

        let balances = group.balances
        #expect(balances.count == 2)

        let aliceBalance = try #require(balances.first { $0.participant.name == "Alice" })
        let bobBalance = try #require(balances.first { $0.participant.name == "Bob" })

        #expect(aliceBalance.amount == Money(cents: 1500))
        #expect(bobBalance.amount == Money(cents: -1500))
    }

    @Test("The settle-up list points from the debtor to the payer")
    func transfersAfterExpense() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )

        let transfers = group.transfers
        #expect(transfers.count == 1)
        #expect(transfers.first?.from.name == "Bob")
        #expect(transfers.first?.to.name == "Alice")
        #expect(transfers.first?.amount == Money(cents: 1500))
    }

    /// The behaviour the "Split Among" footer describes: a payer left out of
    /// the split is covering the cost for others and is owed all of it.
    @Test("Paying on someone else's behalf is recorded in full")
    func payerExcludedFromSplit() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Bob's ticket",
            amount: Money(amount: 20.00),
            paidBy: alice,
            splitAmong: [bob],
            in: group
        )

        let aliceBalance = try #require(group.balances.first { $0.participant.name == "Alice" })
        #expect(aliceBalance.amount == Money(cents: 2000))
    }

    @Test("A group with no expenses still lists its members at zero")
    func emptyGroupBalances() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        try store.addMember(named: "Alice", to: group)
        try store.addMember(named: "Bob", to: group)

        let balances = group.balances
        #expect(balances.count == 2)
        let allZero = balances.allSatisfy { $0.amount.isZero }
        #expect(allZero)
        #expect(group.transfers.isEmpty)
    }

    // MARK: - Editing

    @Test("Editing an expense rewrites it in place rather than replacing it")
    func updateKeepsOneRecord() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)
        let id = expense.id
        let objectID = expense.objectID

        try store.update(
            expense,
            title: "Dinner and drinks",
            amount: Money(amount: 50.00),
            paidBy: bob,
            splitAmong: [alice, bob]
        )

        // One record, same identity — which is what makes CloudKit send a
        // modification rather than a delete and an insert.
        #expect(try context.count(for: Expense.fetchRequest()) == 1)
        #expect(expense.objectID == objectID)
        #expect(expense.id == id)
        #expect(expense.title == "Dinner and drinks")

        #expect(group.totalSpent == Money(cents: 5000))
        let bobBalance = try #require(group.balances.first { $0.participant.name == "Bob" })
        #expect(bobBalance.amount == Money(cents: 2500))
    }

    /// An edit corrects what was recorded; it does not move the expense to
    /// today, which would reshuffle the list under the user.
    @Test("Editing leaves the original date alone")
    func updateKeepsTheDate() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice], in: group
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)

        let original = Date(timeIntervalSince1970: 1_000_000)
        expense.date = original

        try store.update(
            expense, title: "Dinner", amount: Money(amount: 31.00),
            paidBy: alice, splitAmong: [alice]
        )

        #expect(expense.date == original)
    }

    /// Leaving the code behind would keep rendering a foreign receipt under an
    /// expense that no longer has one.
    @Test("Editing away a foreign currency clears its provenance")
    func updateClearsForeignProvenance() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Kraków", currencyCode: "EUR")
        let alice = try store.addMember(named: "Alice", to: group)

        let foreign = try #require(ForeignAmount(amount: 100.00, currencyCode: "PLN", rate: 4.0))
        try store.addExpense(
            title: "Lunch", amount: foreign.converted,
            paidBy: alice, splitAmong: [alice], in: group, paidIn: foreign
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)
        #expect(expense.foreignAmount != nil)

        try store.update(
            expense, title: "Lunch", amount: Money(amount: 25.00),
            paidBy: alice, splitAmong: [alice]
        )

        #expect(expense.foreignAmount == nil)
        #expect(expense.originalCurrencyCode == nil)
    }

    // MARK: - Weighted splits

    @Test("Shares divide an expense unevenly through the bridge")
    func weightedSplit() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        let aliceID = try #require(alice.id)
        let bobID = try #require(bob.id)

        try store.addExpense(
            title: "Room", amount: Money(amount: 90.00),
            paidBy: alice, splitAmong: [alice, bob], in: group,
            shares: [aliceID: 2, bobID: 1]
        )

        let aliceBalance = try #require(group.balances.first { $0.participant.name == "Alice" })
        let bobBalance = try #require(group.balances.first { $0.participant.name == "Bob" })

        // Alice takes two thirds of her own 90.00, so she is owed Bob's third.
        #expect(aliceBalance.amount == Money(cents: 3000))
        #expect(bobBalance.amount == Money(cents: -3000))
    }

    /// The whole path a real split takes: percentages written by the form,
    /// through the JSON overlay, back out of the bridge and into balances.
    ///
    /// Wrocław → Trzcińsko: 145.01 zł, six people, one student fare at 51% off.
    ///
    /// The ids are pinned rather than left to the `UUID()` in `addMember`, and
    /// that is the whole reason this test is reliable. Five travellers on a full
    /// share come out with five *identical* fractional remainders, and
    /// `Money.split(among:)` gives the two leftover cents to the earliest
    /// positions — which `SettlementCalculator` orders by id. Invent fresh ids
    /// each run and the pair is a different two travellers every time, so this
    /// test's cent-exact expectations held about two runs in five.
    ///
    /// Nothing is wrong with the app: `precedes` sorts a given set of ids the
    /// same way on every device, so the split is stable wherever it is computed.
    /// Only a test that draws new ids on each run sees the tie move.
    @Test("A discounted fare divides correctly end to end")
    func discountedFareThroughTheStore() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Trzcińsko", currencyCode: "PLN")

        let names = ["Ala", "Bartek", "Celina", "Darek", "Ewa"]
        let travellers = try names.enumerated().map { index, name in
            let traveller = try store.addMember(named: name, to: group)
            traveller.id = Self.orderedID(UInt8(index + 1))
            return traveller
        }
        let student = try store.addMember(named: "Franek", to: group)
        student.id = Self.orderedID(6)
        try context.save()

        var shares: [UUID: Int] = [:]
        for traveller in travellers {
            shares[try #require(traveller.id)] = 100
        }
        shares[try #require(student.id)] = 49

        try store.addExpense(
            title: "Bilety",
            amount: Money(cents: 14501),
            paidBy: travellers[0],
            splitAmong: Set(travellers + [student]),
            in: group,
            shares: shares
        )

        let balances = group.balances
        func balance(of name: String) throws -> Money {
            try #require(balances.first { $0.participant.name == name }).amount
        }

        #expect(try balance(of: "Franek") == Money(cents: -1294))

        // The buyer fronted the lot, so they are owed everything but their own
        // share of it.
        #expect(try balance(of: "Ala") == Money(cents: 14501) - Money(cents: 2642))

        // 145.01 zł over 549 share-units leaves every full share at 2641 and a
        // remainder of two cents. Those go to the two earliest ids — Ala and
        // Bartek, by the pinning above — and the rest pay the truncated share.
        // Asserted per person because this is exactly what used to drift.
        #expect(try balance(of: "Bartek") == Money(cents: -2642))
        #expect(try balance(of: "Celina") == Money(cents: -2641))
        #expect(try balance(of: "Darek") == Money(cents: -2641))
        #expect(try balance(of: "Ewa") == Money(cents: -2641))

        // Nothing lost to rounding across six people and a 49% share.
        #expect(balances.reduce(Money.zero) { $0 + $1.amount } == .zero)
    }

    /// A uniform weighting is an even split, and storing it as one keeps the
    /// ordinary expense identical to what it was before weights existed —
    /// which is what a client on the old model will read it as.
    /// The screens all fall back on a *missing* title. An empty string is not
    /// missing — it satisfies `title ?? "Untitled"` and draws a blank line
    /// where the fallback belongs — so a blank title has to reach the store as
    /// `nil` rather than as `""`.
    @Test("A blank title is stored as no title at all")
    func blankTitlesAreStoredAsNil() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "   ", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)
        #expect(expense.title == nil)

        // And the balances are untouched by any of it: a title is a label on an
        // expense, never part of what one is worth.
        let bobBalance = try #require(group.balances.first { $0.participant.name == "Bob" })
        #expect(bobBalance.amount == Money(cents: -1500))
    }

    @Test("An expense keeps a title that is only surrounded by whitespace")
    func titlesAreTrimmedNotDiscarded() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        try store.addExpense(
            title: "  Dinner  ", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice], in: group
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)
        #expect(expense.title == "Dinner")
    }

    @Test("A uniform weighting is stored as no weighting at all")
    func uniformWeightsAreNotStored() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        let aliceID = try #require(alice.id)
        let bobID = try #require(bob.id)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group,
            shares: [aliceID: 3, bobID: 3]
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)

        #expect(expense.shareWeights.isEmpty)
        let bobBalance = try #require(group.balances.first { $0.participant.name == "Bob" })
        #expect(bobBalance.amount == Money(cents: -1500))
    }

    /// Otherwise a weight left behind by a removed sharer would come back from
    /// nowhere if they were ever added to the expense again.
    @Test("Weights for members dropped from the split are discarded")
    func weightsAreScopedToTheSplit() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)
        let carol = try store.addMember(named: "Carol", to: group)

        let aliceID = try #require(alice.id)
        let bobID = try #require(bob.id)
        let carolID = try #require(carol.id)

        try store.addExpense(
            title: "Room", amount: Money(amount: 90.00),
            paidBy: alice, splitAmong: [alice, bob], in: group,
            shares: [aliceID: 2, bobID: 1, carolID: 5]
        )
        let expense = try #require((group.expenses as? Set<Expense>)?.first)

        #expect(expense.shareWeights[carolID] == nil)
        #expect(expense.shareWeights.count == 2)
    }

    // MARK: - Dating an expense

    /// The point of the feature: somebody installs Dutch on day three of a trip
    /// and wants days one and two in it. Nothing in the model changed for this
    /// — `Expense.date` has been an optional `Date` since v1 — so what is worth
    /// asserting is that the parameter reaches storage at all.
    @Test("An expense can be recorded as having happened earlier")
    func expenseCanBeBackdated() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        let tuesday = Date(timeIntervalSinceNow: -5 * 24 * 60 * 60)
        try store.addExpense(
            title: "Taxi", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice], in: group, on: tuesday
        )

        let expense = try #require(group.expenseSet.first)
        #expect(expense.date == tuesday)
    }

    /// The default is what keeps the intents and `ScreenshotSeed` — neither of
    /// which has a field to ask with — working unchanged.
    @Test("Leaving the date out still stamps now")
    func addedExpenseDefaultsToNow() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        let before = Date()
        try store.addExpense(
            title: "Coffee", amount: Money(amount: 4.00),
            paidBy: alice, splitAmong: [alice], in: group
        )

        let stored = try #require(group.expenseSet.first?.date)
        #expect(stored >= before)
        #expect(stored <= Date())
    }

    /// The invariant that survived inverting `update`'s old rule: an edit may
    /// move the date, but never *implicitly*. The form passes `nil` when its
    /// picker was not touched, and a dateless record — one caught mid-sync —
    /// must come out of an unrelated edit still dateless rather than stamped
    /// with today.
    @Test("An edit that doesn't mention the date leaves it exactly as it was")
    func updateWithoutDateLeavesItAlone() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        let tuesday = Date(timeIntervalSinceNow: -5 * 24 * 60 * 60)
        try store.addExpense(
            title: "Taxi", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice], in: group, on: tuesday
        )
        let expense = try #require(group.expenseSet.first)

        try store.update(
            expense, title: "Airport taxi", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice]
        )
        #expect(expense.date == tuesday)

        // And the dateless case, which is the one the old comment protected.
        expense.date = nil
        try store.update(
            expense, title: "Taxi to hotel", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice]
        )
        #expect(expense.date == nil)
    }

    @Test("An edit that does mention the date moves it")
    func updateWithDateMovesIt() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)

        try store.addExpense(
            title: "Taxi", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice], in: group
        )
        let expense = try #require(group.expenseSet.first)

        let monday = Date(timeIntervalSinceNow: -6 * 24 * 60 * 60)
        try store.update(
            expense, title: "Taxi", amount: Money(amount: 40.00),
            paidBy: alice, splitAmong: [alice], on: monday
        )

        #expect(expense.date == monday)
    }

    /// Settling up gets the same field, from the same sheet that carries the
    /// partial amount.
    @Test("A payment can be recorded as having happened earlier")
    func paymentCanBeBackdated() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )

        let tuesday = Date(timeIntervalSinceNow: -5 * 24 * 60 * 60)
        try store.recordPayment(
            from: bob, to: alice, amount: Money(amount: 15.00), in: group, on: tuesday
        )

        let payment = try #require(group.expenseSet.first { $0.isReimbursement })
        #expect(payment.date == tuesday)
        // Backdating settles it just the same — the maths never reads the date.
        #expect(group.isSettled)
    }

    // MARK: - Settling up

    /// The whole design rests on this: a payment is an ordinary expense paid by
    /// the debtor and shared by the creditor, so the settlement maths needs no
    /// concept of settling at all.
    @Test("Recording a payment settles the debt it was suggested for")
    func recordPaymentSettles() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )

        let transfer = try #require(group.transfers.first)
        #expect(transfer.from.name == "Bob")

        try store.recordPayment(from: bob, to: alice, amount: transfer.amount, in: group)

        #expect(group.isSettled)
        #expect(group.transfers.isEmpty)
    }

    /// Paying somebody back moves money but buys nothing, and counting it as
    /// spending would inflate the trip's total every time anyone settled up.
    @Test("A payment is not spending")
    func paymentIsNotSpending() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        try store.recordPayment(from: bob, to: alice, amount: Money(amount: 15.00), in: group)

        #expect(group.totalSpent == Money(cents: 3000))
        #expect(group.spending.count == 1)
        #expect(group.settlement().spendingCount == 1)
        // Still two rows in the list — the payment is visible, just not spending.
        #expect(group.expenseSet.count == 2)
    }

    /// The whole of feature 23: the store was always able to write a smaller
    /// figure, and only `TransferRow` insisted on the full one. What it must
    /// not do is *remember* the instalment — the settlement is recomputed from
    /// balances, so the remainder has to come back as an ordinary suggested
    /// transfer rather than as a half-paid row.
    @Test("Part of a debt can be paid, and the rest stays owing")
    func partialPaymentLeavesRemainder() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        // Bob owes Alice 1000.
        try store.addExpense(
            title: "Flights", amount: Money(amount: 2000.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        #expect(group.transfers.first?.amount == Money(cents: 100_000))

        // Five instalments of 200 clear it, and nothing before the last one
        // reports the group as settled.
        for instalment in 1 ... 5 {
            try store.recordPayment(from: bob, to: alice, amount: Money(amount: 200), in: group)

            if instalment < 5 {
                #expect(!group.isSettled)
                let owed = Money(cents: 100_000 - instalment * 20_000)
                #expect(group.transfers.first?.amount == owed)
            }
        }

        #expect(group.isSettled)
        #expect(group.transfers.isEmpty)
        // Five rows to undo individually, not one lump the user cannot unpick.
        #expect(group.expenseSet.filter(\.isReimbursement).count == 5)
        // And still one purchase: instalments buy nothing either.
        #expect(group.totalSpent == Money(cents: 200_000))
    }

    /// Undo is free, and per instalment. Backing one payment out restores
    /// exactly that much of the debt and leaves the others alone.
    @Test("Undoing one instalment restores only that instalment")
    func undoingOneInstalment() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Flights", amount: Money(amount: 2000.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        try store.recordPayment(from: bob, to: alice, amount: Money(amount: 200), in: group)
        try store.recordPayment(from: bob, to: alice, amount: Money(amount: 300), in: group)
        #expect(group.transfers.first?.amount == Money(cents: 50_000))

        let first = try #require(
            group.expenseSet
                .filter(\.isReimbursement)
                .first { $0.amount == 200 }
        )
        try store.delete(first)

        #expect(group.transfers.first?.amount == Money(cents: 70_000))
        #expect(group.expenseSet.filter(\.isReimbursement).count == 1)
    }

    @Test("Deleting a payment puts the debt back")
    func deletingPaymentRestoresDebt() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner", amount: Money(amount: 30.00),
            paidBy: alice, splitAmong: [alice, bob], in: group
        )
        try store.recordPayment(from: bob, to: alice, amount: Money(amount: 15.00), in: group)
        #expect(group.isSettled)

        let payment = try #require(group.expenseSet.first { $0.isReimbursement })
        #expect(payment.reimbursementRecipient == alice)

        try store.delete(payment)

        #expect(!group.isSettled)
        #expect(group.transfers.first?.amount == Money(cents: 1500))
    }

    @Test("Amounts entered in major units survive the round trip to cents")
    func amountRoundTrip() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)
        let carol = try store.addMember(named: "Carol", to: group)

        // 10.00 three ways is the classic case for losing a cent.
        try store.addExpense(
            title: "Taxi",
            amount: Money(amount: 10.00),
            paidBy: alice,
            splitAmong: [alice, bob, carol],
            in: group
        )

        let total = group.balances.reduce(Money.zero) { $0 + $1.amount }
        #expect(total == .zero)
    }
}
