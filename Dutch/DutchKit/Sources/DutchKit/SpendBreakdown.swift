/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// One line of a spend breakdown: a bucket, what it came to, and how much of
/// the whole that is.
///
/// `key` is optional because "not filed under anything" is a real bucket that
/// has to appear — a breakdown that silently dropped uncategorised spending
/// would show bars that do not add up to the total printed above them.
public struct SpendSlice<Key: Hashable & Comparable & Sendable>: Hashable, Sendable {
    public let key: Key?
    public let total: Money
    /// `total` as a share of the whole, in `0...1`. Zero when the whole is
    /// zero — see `SpendBreakdown.slices(of:)`.
    public let fraction: Double

    public init(key: Key?, total: Money, fraction: Double) {
        self.key = key
        self.total = total
        self.fraction = fraction
    }
}

/// Turns a flat list of categorised amounts into the lines of a chart.
///
/// Generic over the bucket, and therefore free of anything the app knows: the
/// category type is a SwiftUI-side enum with localized labels, none of which
/// this needs in order to add money up and put it in order.
public enum SpendBreakdown {

    /// Sums by bucket and orders the result for display.
    ///
    /// The ordering is the whole reason this is testable code rather than a
    /// `sorted(by:)` inside a view body:
    ///
    /// - **Biggest first**, which is the question a breakdown answers.
    /// - **The `nil` bucket always last**, however large it is. It is the
    ///   absence of an answer rather than one of the answers, and a chart whose
    ///   first and longest bar is "we don't know" leads with the one line that
    ///   says nothing.
    /// - **Ties broken by the key**, because `sorted(by:)` is *not* stable in
    ///   Swift. Two buckets that came to the same figure could otherwise swap
    ///   places between one redraw and the next — on a screen that redraws on
    ///   every tap, that is a chart that shuffles while you look at it.
    ///
    /// - Parameter amounts: bucket and figure, in any order, with repeats. The
    ///   caller does not have to group first.
    /// - Returns: one slice per distinct bucket, ordered as above. Buckets
    ///   summing to zero are kept: a category somebody used is a category they
    ///   will look for, and a missing line reads as a bug where a zero-length
    ///   bar reads as a zero.
    public static func slices<Key>(
        of amounts: some Sequence<(key: Key?, amount: Money)>
    ) -> [SpendSlice<Key>] {
        var totals: [Key?: Money] = [:]
        for entry in amounts {
            totals[entry.key, default: .zero] += entry.amount
        }

        // Guarded rather than trusted. An all-zero log is a real state — a group
        // of free events, or a single expense entered as 0 — and dividing by it
        // would make every fraction `nan`, which draws as nothing at all rather
        // than as an obvious mistake.
        let whole = totals.values.reduce(Money.zero, +)
        let divisor = whole.isZero ? 0 : Double(whole.cents)

        return totals
            .map { key, total in
                SpendSlice(
                    key: key,
                    total: total,
                    fraction: divisor == 0 ? 0 : Double(total.cents) / divisor
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.key, rhs.key) {
                case (nil, nil): false
                case (nil, _): false
                case (_, nil): true
                case (let left?, let right?):
                    lhs.total == rhs.total ? left < right : lhs.total > rhs.total
                }
            }
    }
}
