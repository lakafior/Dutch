/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// The two halves of a decimal text field: reading what somebody typed into
/// one, and writing a stored figure back into one.
///
/// They are here as a pair because they only work as a pair — the formatter
/// must never emit anything the parser cannot read back. That is not
/// hypothetical: `text` suppresses grouping separators precisely because
/// `parse` would otherwise take a prefilled `4 411` and hand back `4`,
/// turning a figure the user was shown into a silently different one they
/// were charged.
///
/// In the package rather than beside the form that first needed it, because
/// the second screen to prefill a currency field would otherwise copy the
/// pair — and the copy is where the comma case gets dropped from one of them.
public enum DecimalInput {

    /// Reads a figure as typed into a `.decimalPad` field.
    ///
    /// Accepts either decimal separator. The pad shows whichever the device
    /// locale uses, but people type the one their keyboard muscle memory
    /// reaches for, and the pad emits no grouping separators to confuse this.
    ///
    /// - Returns: The value, or `nil` when the text is not a figure above
    ///   zero — so a caller can treat "not valid yet" and "empty" alike and
    ///   simply leave its confirm button disabled.
    public static func parse(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    /// Renders a stored value for prefilling such a field.
    ///
    /// Trailing zeros are dropped — a field showing `12` rather than `12.00`
    /// is one the user can extend by typing rather than one they must first
    /// delete from. `precision` is the *most* it will show; exchange rates
    /// need six places where an amount needs two.
    ///
    /// The separator is the device's, which is the one the pad will show. The
    /// `locale` argument exists so a test can pin it — the same reason
    /// `Money.formatted(currencyCode:locale:)` takes one, and the only way to
    /// assert this against a fixed string on a machine set to any locale.
    public static func text(
        _ value: Double,
        precision: Int = 2,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0 ... precision))
                .grouping(.never)
                .locale(locale)
        )
    }
}
