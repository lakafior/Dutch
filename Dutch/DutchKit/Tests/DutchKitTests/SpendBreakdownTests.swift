/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

@Suite("Spend breakdown")
struct SpendBreakdownTests {

    private func slices(
        _ pairs: [(String?, Int)]
    ) -> [SpendSlice<String>] {
        SpendBreakdown.slices(
            of: pairs.map { (key: $0.0, amount: Money(cents: $0.1)) }
        )
    }

    @Test("Amounts are summed per bucket")
    func sumsPerBucket() {
        let result = slices([("food", 1000), ("food", 500), ("taxi", 300)])

        #expect(result.count == 2)
        #expect(result[0].key == "food")
        #expect(result[0].total == Money(cents: 1500))
        #expect(result[1].total == Money(cents: 300))
    }

    @Test("Biggest first")
    func biggestFirst() {
        let result = slices([("small", 100), ("big", 900), ("middle", 500)])
        #expect(result.map(\.key) == ["big", "middle", "small"])
    }

    /// The rule that needed a home: uncategorised is the absence of an answer,
    /// so it goes last however large it is.
    @Test("The nil bucket sorts last even when it is the largest")
    func nilSortsLast() {
        let result = slices([("food", 100), (nil, 9000), ("taxi", 50)])

        #expect(result.map(\.key) == ["food", "taxi", nil])
        #expect(result.last?.total == Money(cents: 9000))
    }

    /// `sorted(by:)` is not stable in Swift, so equal totals need a decided
    /// order or the chart reshuffles between redraws.
    @Test("Equal totals are broken by key, and the order is repeatable")
    func tiesAreDeterministic() {
        let pairs: [(String?, Int)] = [("delta", 500), ("alpha", 500), ("charlie", 500)]
        let first = slices(pairs)

        #expect(first.map(\.key) == ["alpha", "charlie", "delta"])
        // Same input, same answer — run repeatedly because an unstable sort can
        // agree with itself once by luck.
        for _ in 0 ..< 20 {
            #expect(slices(pairs).map(\.key) == first.map(\.key))
        }
        // And from a different input order, since the buckets arrive from a
        // dictionary whose iteration order is not promised.
        #expect(slices(pairs.reversed()).map(\.key) == first.map(\.key))
    }

    @Test("Fractions are shares of the whole and sum to one")
    func fractions() {
        let result = slices([("a", 2500), ("b", 2500), ("c", 5000)])

        #expect(result[0].fraction == 0.5)
        #expect(result[1].fraction == 0.25)
        #expect(abs(result.reduce(0) { $0 + $1.fraction } - 1) < 0.000_001)
    }

    /// A group of free events is a real state, and `0/0` draws as nothing at
    /// all rather than as an obvious mistake.
    @Test("An all-zero log yields zero fractions, not NaN")
    func zeroTotal() {
        let result = slices([("a", 0), ("b", 0)])

        #expect(result.count == 2)
        for slice in result {
            #expect(slice.fraction == 0)
            #expect(!slice.fraction.isNaN)
        }
    }

    /// A category somebody used is one they will look for; a missing line reads
    /// as a bug where a zero-length bar reads as a zero.
    @Test("A bucket summing to zero is kept alongside non-zero ones")
    func keepsZeroBuckets() {
        let result = slices([("spent", 1000), ("free", 0)])
        #expect(result.map(\.key) == ["spent", "free"])
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(slices([]).isEmpty)
    }

    @Test("A single uncategorised bucket still takes the whole bar")
    func onlyNil() {
        let result = slices([(nil, 4200)])

        #expect(result.count == 1)
        #expect(result[0].key == nil)
        #expect(result[0].fraction == 1)
    }
}
