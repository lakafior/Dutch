/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

    /// The group's identity, and its total once there is one.
    ///
    /// The section itself is unconditional — it is the only thing on this screen
    /// that says *which* group you are looking at, and a group that hasn't been
    /// spent in yet is precisely the one you might have opened by mistake. What
    /// is conditional is the number: a large `0.00` on a brand new group is
    /// noise sitting where the useful figure will eventually be, so until then
    /// the block is the tile and a quiet line about where the group stands.
struct GroupSummarySection: View {
    /// Observed for the group's own fields — its name, currency and appearance.
    @ObservedObject var group: ExpenseGroup
    let contents: GroupContents

    var body: some View {
        Section {
            // The same tile as the list row, so arriving here confirms you
            // opened the group you meant to. Larger, because this is the one
            // place it isn't competing with a column of others.
            HStack(alignment: .top, spacing: 16) {
                GroupIcon(group.appearance, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if contents.spendingCount > 0 {
                        Text(.totalSpent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(contents.totalSpent.formatted(in: group))
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                            .motionContentTransition(.numericText())

                        // Counts the spending, not the rows: settling up adds an
                        // entry to the list below but buys nothing, and "12
                        // expenses" over a total that added up nine of them is
                        // just wrong.
                        Text("\(ItemCount.expenses(contents.spendingCount)) · \(ItemCount.members(contents.members.count))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(.nothingSpentYet)
                            .font(.headline)

                        // Only once there is a roster. "0 members" next to
                        // "nothing spent yet" is the same fact told twice, and
                        // the members section below already asks for the first
                        // one in words.
                        if !contents.members.isEmpty {
                            Text(ItemCount.members(contents.members.count))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: contents.totalSpent)
            .accessibilityElement(children: .combine)

            SpendBreakdownRows(
                rows: contents.spendByCategory,
                currencyCode: group.currency,
                totalSpent: contents.totalSpent
            )

            // Withheld until there is something to summarise: the shared text
            // is the total and the payments settling it, and neither exists yet.
            //
            // Here rather than in the toolbar, for two reasons. The toolbar
            // already owns a share glyph — that one invites people into the
            // group, and hanging a second, different share off the same
            // symbol makes both a coin flip. And this section is exactly
            // the thing being shared: the total, and what it resolves to.
            if contents.spendingCount > 0 {
                ShareLink(
                    item: SharedSummary(summary: contents.summary),
                    preview: SharePreview(group.name ?? String(localized: .unnamedGroup))
                ) {
                    Label("Share Summary", systemImage: "doc.plaintext")
                }
                .accessibilityHint("Copies who owes whom, the total and the expense list as text")
            }
        }
    }
}
