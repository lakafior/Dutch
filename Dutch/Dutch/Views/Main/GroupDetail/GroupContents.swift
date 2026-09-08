/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import Foundation

/// Everything `GroupDetailView` reads off its group, gathered in one pass.
///
/// Ordinary computed properties would be re-evaluated at every mention, and
/// this screen mentions them a lot: the member list alone touched the balances
/// once per row, each time walking every expense and re-running the whole
/// settlement to pull out a single number.
@MainActor
struct GroupContents {
    let members: [Person]
    /// The log, cut into days and newest first — the order the fetch hands it
    /// over in. The flat array it replaced had no readers left once the list
    /// went sectioned.
    let days: [ExpenseDay]
    let balances: [Participant.ID: Money]
    let transfers: [Transfer]
    let totalSpent: Money
    /// How many of the expenses are actual spending rather than settling up.
    let spendingCount: Int

    /// Where the money went, ready to draw — see `SpendBreakdown.slices(of:)`
    /// for the ordering rules and why they are in the package rather than here.
    ///
    /// Computed in the same pass everything else on this screen is, because a
    /// breakdown recomputed inside the summary section's body would walk the
    /// whole log again on every redraw — and this screen redraws on every tap.
    ///
    /// Reimbursements are excluded, as they are from `totalSpent`. A settle-up
    /// buys nothing, so a category breakdown that counted it would attribute
    /// money to a category twice: once when it was spent and once when somebody
    /// paid their share back.
    let spendByCategory: [SpendSlice<ExpenseCategory>]

    /// Members keyed by id, so recording a payment can get from the `Transfer`
    /// the settlement produced back to the `Person` the store needs to write.
    let person: [UUID: Person]

    /// One colour per member, resolved over the whole roster at once — see
    /// `RosterAvatars` for why it cannot be done a row at a time.
    let avatars: RosterAvatars

    /// The same numbers as a snapshot free of managed objects, ready to be
    /// rendered as shareable text. Built here because everything it needs is
    /// already in hand — it costs one more pass over `expenses`, not another
    /// settlement.
    let summary: GroupSummary

    /// Takes the roster and the log already sorted, because they arrive from
    /// fetch requests that sorted them in SQLite — see `Person.request(in:)`.
    init(group: ExpenseGroup, members roster: [Person], expenses log: [Expense]) {
        members = roster

        // A single pass, because `log` is already sorted by date descending —
        // see `Expense.request(in:)`. A record with no date at all gets its own
        // bucket rather than being dropped: it sorts last out of SQLite, so the
        // bucket lands at the bottom, and a row missing from the log would be
        // money missing from the screen.
        let calendar = Calendar.current
        days = log.reduce(into: []) { days, expense in
            let day = expense.date.map(calendar.startOfDay(for:)) ?? .distantPast
            if days.last?.day == day {
                days[days.count - 1].expenses.append(expense)
            } else {
                days.append(ExpenseDay(day: day, expenses: [expense]))
            }
        }

        person = Dictionary(
            roster.compactMap { member in member.id.map { ($0, member) } },
            uniquingKeysWith: { first, _ in first }
        )

        avatars = RosterAvatars(roster)

        let settlement = group.settlement(members: roster, expenses: log)
        balances = settlement.balanceByParticipant
        transfers = settlement.transfers
        totalSpent = settlement.totalSpent
        spendingCount = settlement.spendingCount

        summary = group.summary(from: settlement, expenses: log, memberCount: roster.count)

        spendByCategory = SpendBreakdown.slices(
            of: log
                .lazy
                .filter { !$0.isReimbursement }
                .map { (key: $0.category, amount: Money(amount: $0.amount)) }
        )
    }
}
