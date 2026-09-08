/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// One row of the expense log — an expense, or a settling-up payment.
struct ExpenseLogRow: View {
    let expense: Expense
    /// The payer's avatar, resolved over the whole roster by `GroupContents`.
    let avatar: PersonAvatar?
    let currencyCode: String
    /// Takes back a recorded settlement.
    let onUndo: (Expense) -> Void
    /// Opens the form on this expense, to correct it or to copy it.
    let onOpen: (Expense, FormTarget.Mode) -> Void

    var body: some View {
        // Payments are not editable: there is nothing in one to correct except
        // whether it happened, and that is what deleting it says. Ordinary
        // expenses open the form.
        if expense.isReimbursement {
            PaymentRow(expense: expense, currencyCode: currencyCode)
                // Replaces the section's `onDelete` for this row alone.
                //
                // A payment is not something the user entered — it is an
                // assertion that a debt was settled — so the way back out of it
                // is an *undo*, and removing the record is merely how that is
                // implemented. Labelled "Delete", the only correction available
                // read as data loss: the first outside report of this came from
                // someone who marked a transfer paid by accident, swiped left
                // expecting to destroy something, and was surprised to find the
                // debt restored instead.
                //
                // Still `.destructive`, because a record does go away and the
                // red is honest about that. It is the word that was wrong.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onUndo(expense)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                }
        } else {
            Button {
                onOpen(expense, .edit)
            } label: {
                ExpenseRow(
                    expense: expense,
                    // From the same roster the members list is drawn from, not
                    // derived here: an expense whose payer showed one colour on
                    // one section and another two sections down would be worse
                    // than no colour at all.
                    avatar: avatar,
                    currencyCode: currencyCode
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the expense for editing")
            // Long-press rather than a swipe action or a button on the row:
            // repeating an expense is common enough to want and rare enough
            // that it shouldn't take up space in a list people mostly read.
            // Payments are left out — a settlement is recorded from the section
            // above, and paying the same debt twice is a mistake, not a
            // shortcut.
            .contextMenu {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    onOpen(expense, .duplicate)
                }
            }
        }
    }
}
