/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Lays already-known amounts against a total and turns what is left into one
/// exact weighting.
///
/// The bill is itemised and the numbers are on the receipt: Ania's salad 23.50,
/// Marek's steak 68.00, Kuba's pasta 35.50 of a 127.00 card payment. Getting
/// there through percentages means working out 18.5 / 53.5 / 28 first, which is
/// the arithmetic this app exists to delete.
///
/// **Nothing new is stored to do this.** The output is the same
/// `[Participant.ID: Int]` weighting `ExpenseEntry` has always taken — the
/// weights are simply *cents* rather than percentages. That works because
/// `Money.split(among:)` allocates `cents * weight / total`: feed it weights
/// that are themselves the cents and sum to the whole, and every share comes
/// back exactly, with no remainder left to redistribute. `ExpenseEntry.shares`
/// documents that weights are relative and that nothing depends on reading them
/// as percentages, which is precisely what this relies on.
///
/// The consequence worth knowing is that a client too old to have heard of this
/// feature still divides the expense **correctly**: it decodes the same
/// integers and applies the same proportional split, arriving at the same cents.
/// That is a better outcome than the percentage weighting shipped with, where a
/// client predating the attribute fell back to an even split.
public enum ExactSplit {

    /// What a set of fixed amounts comes to against a total.
    public struct Plan: Sendable, Equatable {
        /// The weighting to store and to settle with, in cents.
        ///
        /// Empty when the plan cannot be satisfied — there is no partially
        /// correct weighting to hand back, and returning one anyway would put
        /// a wrong split in front of somebody as though it were a real answer.
        public let weights: [Participant.ID: Int]

        /// The total less the fixed amounts: what the unfixed rows divide
        /// between them. Negative when the fixed amounts overshoot.
        ///
        /// This is the figure a form has to keep on screen the whole time.
        /// Without it the fixed rows are being typed against a total the user
        /// is holding in their head, which is the thing that makes an
        /// exact-amount split feel like arithmetic homework.
        public let remainder: Money

        /// Whether `weights` describes a split that actually adds up.
        ///
        /// Two ways it doesn't, and they read differently on screen so the
        /// caller is left to phrase them: the fixed amounts come to more than
        /// the bill, or they come to less and nobody is left to absorb what
        /// remains.
        public let isSatisfiable: Bool

        /// The fixed amounts exceed the total.
        public var overshoots: Bool { remainder < .zero }
    }

    /// Combines fixed amounts and relative weights into one exact weighting.
    ///
    /// - Parameters:
    ///   - total: the whole expense, tip included — whatever is actually being
    ///     divided.
    ///   - fixed: participants whose figure the receipt already gave.
    ///   - sharing: participants still expressed relatively, as the app's
    ///     percentages of a full share. They divide whatever the fixed amounts
    ///     leave behind.
    /// - Returns: a plan whose `weights` sum to exactly `total` in cents
    ///   whenever `isSatisfiable`.
    public static func plan(
        total: Money,
        fixed: [Participant.ID: Money],
        sharing: [Participant.ID: Int]
    ) -> Plan {
        // Passed straight through rather than converted. An ordinary weighted
        // split has no fixed amounts, and rewriting its percentages as cents
        // would change what gets stored for a feature that was working — and
        // with it what the edit form reads back out.
        guard !fixed.isEmpty else {
            return Plan(weights: sharing, remainder: total, isSatisfiable: true)
        }

        // A negative figure can't come from the form's currency field, but it
        // must not be allowed to reach the weighting: a negative weight is
        // filtered out by `ExpenseEntry`, which would silently drop that person
        // from the split and leave everyone else's weights summing to less than
        // the total — a plausible-looking bill that charges the wrong amounts.
        guard fixed.values.allSatisfy({ !($0 < .zero) }) else {
            return Plan(weights: [:], remainder: total, isSatisfiable: false)
        }

        let remainder = total - fixed.values.reduce(Money.zero, +)
        guard !(remainder < .zero) else {
            return Plan(weights: [:], remainder: remainder, isSatisfiable: false)
        }

        var weights = fixed.mapValues(\.cents)

        // Every row is fixed. The parts have to reconstruct the whole on their
        // own, because there is nobody left to take up the difference.
        let sharers = sharing.filter { $0.value > 0 }
        guard !sharers.isEmpty else {
            let exact = remainder.isZero
            return Plan(
                weights: exact ? weights : [:],
                remainder: remainder,
                isSatisfiable: exact
            )
        }

        // Through the calculator rather than divided here, for the reason
        // `slices(of:among:)` is public at all: a second implementation of "how
        // an expense divides" disagrees by a cent on exactly the splits people
        // are looking hardest at. It also carries the id ordering that makes
        // the leftover land on the same person on every device.
        for (participant, slice) in SettlementCalculator.slices(of: remainder, among: sharers) {
            weights[participant] = slice.cents
        }

        return Plan(weights: weights, remainder: remainder, isSatisfiable: true)
    }
}
