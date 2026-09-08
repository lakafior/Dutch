/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

/// A settling-up payment in the expense list.
///
/// Rendered as a sentence rather than a title and an amount, because that is
/// what it is: money that moved between two people and bought nothing. It sits
/// in the same list as the expenses so it can be deleted the same way — which
/// is the only undo a mis-tapped "Mark Paid" needs.
struct PaymentRow: View {
    let expense: Expense
    let currencyCode: String

    /// The width of an expense row's avatar, tracked so the two kinds of row in
    /// this list start their text on the same column. Same base, same
    /// relative-to and same cap as `PersonIcon`, so they stay together at every
    /// type size rather than only at the default one.
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 26

    private var sentence: String {
        let payer = expense.paidBy?.name ?? "?"
        let recipient = expense.reimbursementRecipient?.name ?? "?"
        return String(
            localized: "\(payer) paid \(recipient)",
            comment: "A settling-up payment in the expense log. Both placeholders are member names."
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            // A bare glyph rather than a circle: a payment has two people in it
            // and no single colour to carry, and giving it an avatar-shaped mark
            // would make it read as somebody's expense.
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: min(iconSide, 26 * 1.4))
                .accessibilityHidden(true)

            // One line now the day header carries the date. A payment has no
            // title to pair a date with, so dropping it left nothing behind.
            Text(sentence)
                .font(.callout)

            Spacer(minLength: 12)

            // Secondary, unlike an expense amount: this figure is not part of
            // what the trip cost, and giving it the same weight as a real
            // expense would suggest it was.
            Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(sentence) \(Money(amount: expense.amount).formatted(currencyCode: currencyCode))"
        )
    }
}
