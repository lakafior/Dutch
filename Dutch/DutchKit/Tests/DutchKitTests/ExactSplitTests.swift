/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

@Suite("Exact amounts in a split")
struct ExactSplitTests {
    private let ania = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    private let marek = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
    private let kuba = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!

    /// The receipt case the feature exists for, and the property everything
    /// else rests on: run the weighting back through the same split the
    /// calculator uses and the typed figures come out untouched.
    @Test("Fixed amounts covering the whole bill are charged exactly")
    func fixedAmountsAreExact() {
        let plan = ExactSplit.plan(
            total: Money(cents: 12_700),
            fixed: [ania: Money(cents: 2_350), marek: Money(cents: 6_800), kuba: Money(cents: 3_550)],
            sharing: [:]
        )

        #expect(plan.isSatisfiable)
        #expect(plan.remainder == .zero)

        let charged = Dictionary(
            uniqueKeysWithValues: SettlementCalculator
                .slices(of: Money(cents: 12_700), among: plan.weights)
                .map { ($0.participant, $0.amount) }
        )
        #expect(charged[ania] == Money(cents: 2_350))
        #expect(charged[marek] == Money(cents: 6_800))
        #expect(charged[kuba] == Money(cents: 3_550))
    }

    @Test("One fixed row, and the rest divide what is left")
    func mixedFixedAndShared() {
        let plan = ExactSplit.plan(
            total: Money(cents: 12_700),
            fixed: [ania: Money(cents: 2_350)],
            sharing: [marek: 100, kuba: 100]
        )

        #expect(plan.isSatisfiable)
        #expect(plan.remainder == Money(cents: 10_350))

        let charged = Dictionary(
            uniqueKeysWithValues: SettlementCalculator
                .slices(of: Money(cents: 12_700), among: plan.weights)
                .map { ($0.participant, $0.amount) }
        )
        #expect(charged[ania] == Money(cents: 2_350))
        #expect(charged[marek]! + charged[kuba]! == Money(cents: 10_350))
    }

    /// An odd remainder still has to reconstruct the whole — the stray cent
    /// goes to somebody rather than evaporating.
    @Test("An indivisible remainder still sums back to the total")
    func remainderSumsBack() {
        let plan = ExactSplit.plan(
            total: Money(cents: 10_000),
            fixed: [ania: Money(cents: 1_999)],
            sharing: [marek: 100, kuba: 100]
        )

        #expect(plan.isSatisfiable)
        #expect(plan.weights.values.reduce(0, +) == 10_000)

        let charged = SettlementCalculator.slices(of: Money(cents: 10_000), among: plan.weights)
        #expect(charged.map { $0.amount }.reduce(Money.zero, +) == Money(cents: 10_000))
    }

    /// Weighted rows keep their proportions against the remainder, not against
    /// the total — the couple sharing a room still pay half each of what is
    /// left after Ania's salad comes off the top.
    @Test("Relative weights apply to the remainder, not the total")
    func weightsApplyToRemainder() {
        let plan = ExactSplit.plan(
            total: Money(cents: 10_000),
            fixed: [ania: Money(cents: 4_000)],
            sharing: [marek: 100, kuba: 50]
        )

        let charged = Dictionary(
            uniqueKeysWithValues: SettlementCalculator
                .slices(of: Money(cents: 10_000), among: plan.weights)
                .map { ($0.participant, $0.amount) }
        )
        #expect(charged[marek] == Money(cents: 4_000))
        #expect(charged[kuba] == Money(cents: 2_000))
    }

    @Test("Fixed amounts over the total are not satisfiable")
    func overshootIsRejected() {
        let plan = ExactSplit.plan(
            total: Money(cents: 5_000),
            fixed: [ania: Money(cents: 4_000), marek: Money(cents: 2_000)],
            sharing: [:]
        )

        #expect(!plan.isSatisfiable)
        #expect(plan.overshoots)
        #expect(plan.remainder == Money(cents: -1_000))
        #expect(plan.weights.isEmpty)
    }

    /// The other way it fails to add up, and it reads differently on screen:
    /// the money is short and there is nobody left to absorb it.
    @Test("Fixed amounts under the total with nobody sharing are not satisfiable")
    func shortfallWithNoSharersIsRejected() {
        let plan = ExactSplit.plan(
            total: Money(cents: 5_000),
            fixed: [ania: Money(cents: 2_000)],
            sharing: [:]
        )

        #expect(!plan.isSatisfiable)
        #expect(!plan.overshoots)
        #expect(plan.remainder == Money(cents: 3_000))
        #expect(plan.weights.isEmpty)
    }

    /// Somebody selected whose share the fixed amounts have already used up.
    /// A real state, and it has to be visible as a zero rather than rejected.
    @Test("A zero remainder charges the sharing rows nothing")
    func zeroRemainderIsAllowed() {
        let plan = ExactSplit.plan(
            total: Money(cents: 5_000),
            fixed: [ania: Money(cents: 5_000)],
            sharing: [marek: 100]
        )

        #expect(plan.isSatisfiable)
        #expect(plan.remainder == .zero)
        #expect(plan.weights[marek] == 0)
    }

    /// An ordinary percentage split has to come through untouched, or every
    /// expense already stored as one would be rewritten the next time it was
    /// edited.
    @Test("With no fixed amounts the weighting passes straight through")
    func percentagesArePassedThrough() {
        let plan = ExactSplit.plan(
            total: Money(cents: 10_000),
            fixed: [:],
            sharing: [ania: 100, marek: 50]
        )

        #expect(plan.isSatisfiable)
        #expect(plan.weights == [ania: 100, marek: 50])
        #expect(plan.remainder == Money(cents: 10_000))
    }

    @Test("A negative fixed amount is refused rather than silently dropped")
    func negativeFixedIsRejected() {
        let plan = ExactSplit.plan(
            total: Money(cents: 5_000),
            fixed: [ania: Money(cents: -100)],
            sharing: [marek: 100]
        )

        #expect(!plan.isSatisfiable)
        #expect(plan.weights.isEmpty)
    }
}
