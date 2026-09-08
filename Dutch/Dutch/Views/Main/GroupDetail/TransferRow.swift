/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

struct TransferRow: View {
    let transfer: Transfer
    let currencyCode: String
    /// Whether the payment is one *this* device's owner has to make.
    let isMe: Bool
    let onSettle: () -> Void
    /// Opens the sheet for handing over less than the whole transfer.
    let onPartial: () -> Void

    /// Wrapped, because this returns a `String` and `Text(payer)` resolves to
    /// the non-localizing initializer — the failure that has no warning and no
    /// stale key, because the string never had a key to begin with.
    private var payer: String {
        isMe ? String(localized: "You") : transfer.from.name
    }

    private var amount: String {
        transfer.amount.formatted(currencyCode: currencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            // One chooser over two *complete* candidates, amount included. The
            // fallback exists to need less width, so hoisting the amount out of
            // both would leave two spellings of the same row and never reach
            // the vertical layout at all.
            ViewThatFits(in: .horizontal) {
                // Preferred, while two names and an amount genuinely share a line.
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(payer).fontWeight(.medium)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transfer.to.name).fontWeight(.medium)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(namesLabel)

                    Spacer(minLength: 12)

                    amountButton
                }

                // Fallback for long names and accessibility text sizes, where the
                // single line used to truncate both names into uselessness.
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(payer) → \(transfer.to.name)")
                        .fontWeight(.medium)
                        .accessibilityLabel(namesLabel)

                    amountButton
                }
            }
            .font(.callout)

            // A visible button, not a swipe action. Settling up is the second
            // thing anyone comes to this screen to do, and hiding it behind a
            // gesture with no affordance means most people never find it.
            // `.borderless` keeps it a hit target of its own inside the row.
            //
            // Still the whole transfer, and still one tap. Paying in full is
            // the common case and the thing this screen exists for, so the
            // partial hangs off the amount instead of competing here.
            Button("Mark Paid", action: onSettle)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    isMe
                        ? "Mark your \(amount) payment to \(transfer.to.name) as paid"
                        : "Mark \(transfer.from.name)'s \(amount) payment to \(transfer.to.name) as paid"
                )
        }
    }

    /// Who pays whom, as one phrase.
    ///
    /// The amount used to be combined into this label. It is a control now, and
    /// a control folded into a combined element is a control VoiceOver cannot
    /// reach — the row would still read correctly and the action would be gone.
    /// The figure is not lost from the reading: it is the next element across.
    private var namesLabel: String {
        isMe
            ? String(localized: "You pay \(transfer.to.name)")
            : String(localized: "\(transfer.from.name) pays \(transfer.to.name)")
    }

    /// The figure, as the way in to paying part of it.
    ///
    /// Tinted rather than plain, because an affordance is the entire argument
    /// for this control existing here: the alternative was a long press, and
    /// the reasoning above about gestures nobody finds applies to a press as
    /// much as to a swipe. The accent colour, not the group's — a settlement
    /// figure is the one number on this screen that must not pick up a tint
    /// that could be read as a balance.
    ///
    /// A button rather than a one-item menu. The menu was the earlier guess and
    /// costs a tap to reach a single entry; the sheet it opens is prefilled
    /// with the full amount anyway, so tapping the figure loses nothing.
    private var amountButton: some View {
        Button(action: onPartial) {
            Text(amount).monospacedDigit()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            isMe
                ? "Pay part of \(amount) to \(transfer.to.name)"
                : "Record part of \(transfer.from.name)'s \(amount) payment to \(transfer.to.name)"
        )
    }
}
