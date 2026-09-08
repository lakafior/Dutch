/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

    /// Where the money went.
    ///
    /// The answer to what a category is *for*. Before this, an expense could be
    /// filed and the app never used the filing — a labelled field that did no
    /// work, which is exactly how it was reported.
    ///
    /// Only once something has been categorised. A group nobody files gets a
    /// single **Uncategorised** bar equal to the total it already read two lines
    /// above, which is a chart of one fact repeated.
    ///
    /// In the summary section rather than on a screen of its own: it belongs
    /// under the total it decomposes, it costs no navigation, and a breakdown
    /// behind a push is one most people would never open — the same argument
    /// that keeps **Share Summary** here instead of in the toolbar.
struct SpendBreakdownRows: View {
    let rows: [SpendSlice<ExpenseCategory>]
    let currencyCode: String
    /// Drives the animation, so the bars move when the total behind them does.
    let totalSpent: Money

    var body: some View {
        if rows.contains(where: { $0.key != nil }) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.key) { row in
                    BreakdownRow(
                        category: row.key,
                        total: row.total,
                        fraction: row.fraction,
                        currencyCode: currencyCode
                    )
                }
            }
            .padding(.vertical, 4)
            .animation(.snappy, value: totalSpent)
        }
    }
}
