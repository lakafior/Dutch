/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

    /// The log, one section per day.
    ///
    /// A week of receipts as one flat list is thirty rows with nothing to hold
    /// on to; the same rows under "Sat 12 July" are a trip somebody can find
    /// their way around. The date left the rows when it arrived in the headers —
    /// a date on every row under a header that already says it is noise sitting
    /// where the payer's name now goes.
struct ExpenseLogSection: View {
    let contents: GroupContents
    let currencyCode: String
    let onAddFirst: () -> Void
    let onUndo: (Expense) -> Void
    let onOpen: (Expense, FormTarget.Mode) -> Void
    let onDelete: (IndexSet, [Expense]) -> Void

    var body: some View {
        if contents.days.isEmpty {
            // Nothing at all until there is a roster. The summary block above
            // already says *Nothing spent yet*, and a grey *No expenses yet.*
            // under an Expenses header is that same sentence a second time, on
            // the one screen that has nothing else to look at — a brand-new
            // group announcing its own emptiness twice before offering anything
            // to do about it. `settleUpSection` above is the precedent: a
            // section with nothing to say does not appear.
            //
            // Once there are members the section returns carrying the *action*
            // rather than a placeholder, which is the rule the rest of this
            // screen follows and the one `membersSection` was fixed to obey.
            // The result is that each stage of a new group offers exactly one
            // next thing to do: add members, then add the first expense.
            if !contents.members.isEmpty {
                Section("Expenses") {
                    Button(action: onAddFirst) {
                        Label("Add the First Expense", systemImage: "plus.circle")
                    }
                }
            }
        } else {
            ForEach(contents.days) { day in
                Section(day.title) {
                    ForEach(day.expenses, id: \.objectID) { expense in
                        ExpenseLogRow(
                            expense: expense,
                            avatar: expense.paidBy.map { contents.avatars[$0] },
                            currencyCode: currencyCode,
                            onUndo: onUndo,
                            onOpen: onOpen
                        )
                    }
                    // Per day, because the offsets a section hands back index
                    // that section. Deleting against the whole log here would
                    // remove whatever sat at the same offset in it — the right
                    // row on the first day and the wrong one on every day
                    // after it.
                    .onDelete { offsets in
                        onDelete(offsets, day.expenses)
                    }
                }
            }
        }
    }
}
