/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

@Suite("Tips")
struct TipTests {

    @Test("No tip leaves the amount exactly as entered")
    func noneIsIdentity() {
        #expect(Tip.none.applied(to: 47.30) == 47.30)
        #expect(Tip.none.isNone)
    }

    @Test("A percentage case behaves as the rate it wraps")
    func wrapsRate() throws {
        let rate = try #require(TipRate(percent: 15))
        #expect(Money(amount: Tip.rate(rate).applied(to: 100)) == Money(cents: 11_500))
    }

    /// The case this whole type was added for: a cover charge that no
    /// percentage expresses without arithmetic done at the table.
    @Test("A flat sum is added on top")
    func addsFlatSum() throws {
        let tip = try #require(Tip.flat(5))
        #expect(Money(amount: tip.applied(to: 47.30)) == Money(cents: 5_230))
    }

    @Test("A flat sum with minor units survives the addition exactly")
    func flatWithMinorUnits() throws {
        let tip = try #require(Tip.flat(2.50))
        #expect(Money(amount: tip.applied(to: 10.10)) == Money(cents: 1_260))
    }

    @Test("A zero flat sum adds nothing and reads as no tip")
    func zeroFlatIsNone() throws {
        let tip = try #require(Tip.flat(0))
        #expect(tip.isNone)
        #expect(tip.applied(to: 12.34) == 12.34)
    }

    @Test("A negative flat sum is refused — a discount is not a tip")
    func rejectsNegativeFlat() {
        #expect(Tip.flat(-1) == nil)
        #expect(Tip.flat(-0.01) == nil)
    }

    @Test("Non-finite input is refused rather than trapping downstream")
    func rejectsNonFinite() {
        #expect(Tip.flat(.nan) == nil)
        #expect(Tip.flat(.infinity) == nil)
    }

    /// Deliberately unbounded, unlike `TipRate.maximumPercent`: 500 is an
    /// ordinary tip in forint and an absurd one in euro, and this type cannot
    /// tell which it is holding. The form's *Saves as…* footer is the check.
    @Test("A large flat sum is accepted, because no currency-free cap exists")
    func acceptsLargeFlat() throws {
        let tip = try #require(Tip.flat(5_000))
        #expect(Money(amount: tip.applied(to: 1_500)) == Money(cents: 650_000))
    }

    /// The reason `applied(to:)` returns a `Double`: rounding stays in one
    /// place, so a tipped bill still splits without losing a cent.
    @Test("A bill with a flat tip still splits back to its own total")
    func flatTippedBillSplitsExactly() throws {
        let tip = try #require(Tip.flat(5))
        let total = Money(amount: tip.applied(to: 47.35))

        let shares = total.split(into: 3)
        #expect(shares.reduce(Money.zero, +) == total)
    }

    /// A flat tip is a figure in the money actually handed over, so it is added
    /// before the conversion rather than after it — the same order a percentage
    /// already followed.
    @Test("A flat tip applies in the currency paid, then converts once")
    func flatAppliesBeforeConversion() throws {
        let tip = try #require(Tip.flat(150))
        let foreign = try #require(
            ForeignAmount(amount: tip.applied(to: 1500), currencyCode: "HUF", rate: 389.15)
        )
        #expect(Money(amount: foreign.amount) == Money(cents: 165_000))
        #expect(foreign.converted == Money(amount: 1650 / 389.15))
    }
}
