/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// A tip, tax or service charge added on top of an entered amount before it is
/// split — expressed either as a percentage of the bill or as a flat sum.
///
/// Two cases and not one field that guesses between them, for the same reason
/// `RowShare` in the expense form is two cases: `50` cannot mean half the bill
/// on one bill and fifty złoty on the next, and a control where it might is one
/// nobody can read at a glance. The kind is a menu choice, and the label always
/// shows which one is in force — `15%` or `5,00 zł`, never a bare `15`.
///
/// The flat case is what a percentage cannot express: a cover charge, a fixed
/// service fee, a rounded-up "keep the change". Before it existed the only way
/// to add 5 zł to a 47,30 bill was to work out that it is 10.57% and type that,
/// standing at a table.
///
/// Nothing here is stored. A tip folds into the amount the expense records — see
/// `applied(to:)` — so this type exists for the seconds between typing a figure
/// and saving it.
public enum Tip: Hashable, Sendable {

    /// A percentage of the amount, which is what a receipt prints.
    case rate(TipRate)

    /// A flat sum, in the currency the amount is being entered in.
    ///
    /// Deliberately the *entered* currency and not the group's. A cover charge
    /// abroad is a figure in the local money, added to a local bill, and the
    /// pair converts once afterwards — the same order `TipRate` already works
    /// in, and the reason `applied(to:)` never converts anything itself.
    case flat(Money)

    /// No tip, and the default everywhere.
    public static let none = Tip.rate(.none)

    /// Whether this adds anything, for call sites deciding whether to mention it.
    public var isNone: Bool {
        switch self {
        case .rate(let rate): rate.isNone
        case .flat(let amount): amount.isZero
        }
    }

    /// A flat tip, or `nil` for a figure that is not one.
    ///
    /// Fails rather than clamping, matching `TipRate.init(percent:)` — the form
    /// treats `nil` as "not valid yet" and leaves the entry alone.
    ///
    /// Negative is refused on the same reasoning as a negative percentage: a
    /// charge that *reduces* the bill is a discount, which is a different
    /// feature wearing this one's control, and a mistyped minus would quietly
    /// lower a total everybody else is splitting.
    ///
    /// **There is deliberately no upper bound here, and that asymmetry with
    /// `TipRate.maximumPercent` is the point.** A percentage can be capped
    /// because 1500% is meaningless in every currency — it is always a missed
    /// decimal point. A flat sum cannot: 500 is an ordinary tip in forint and
    /// an absurd one in euro, and the type has no idea which it is holding. So
    /// the check moves to where the information is — the form's *Saves as…*
    /// footer, which spells out the resulting total in words before Save, and
    /// which is already the only thing standing between a mistyped amount and a
    /// wrong balance.
    public static func flat(_ amount: Double) -> Tip? {
        guard amount.isFinite, amount >= 0 else { return nil }
        return .flat(Money(amount: amount))
    }

    /// The amount with the tip added.
    ///
    /// Takes and returns a `Double` in major units, exactly like
    /// `TipRate.applied(to:)` and for exactly that reason: the figure an
    /// expense stores is rounded to minor units once and only once, downstream,
    /// in `Money.init(amount:)` or in `ForeignAmount.converted`. That single
    /// rounding is what keeps `Money.split`'s promise that the shares add back
    /// up to the total.
    ///
    /// The flat case adds no rounding point of its own even though it holds a
    /// `Money`: `amount` is a plain division by 100, so a tip typed as 5,00
    /// contributes 5.0 and nothing is rounded until the sum reaches `Money`.
    /// Holding the flat sum as cents rather than as a `Double` is what makes
    /// that true — 0.1 + 0.2 arithmetic never happens to the tip itself.
    public func applied(to amount: Double) -> Double {
        switch self {
        case .rate(let rate): rate.applied(to: amount)
        case .flat(let flat): amount + flat.amount
        }
    }
}
