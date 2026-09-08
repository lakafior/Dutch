/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

/// One line of the spend breakdown: what it was, how much, and how much of the
/// total that is.
///
/// The bar earns its place by answering the question the figures alone don't —
/// *most of this trip was accommodation* is a glance, where four amounts in a
/// column is arithmetic. It is the group's own tint rather than a colour per
/// category: twelve categories would need twelve colours, the palette has eight
/// and deliberately excludes the two the balances already spend, and a chart
/// whose colours are reused every eight rows tells the reader nothing.
struct BreakdownRow: View {
    let category: ExpenseCategory?
    let total: Money
    /// In `0...1`, and never `nan` — `SpendBreakdown` guards the zero-total case
    /// so this view does not have to.
    let fraction: Double
    let currencyCode: String

    @Environment(\.expenseGroupTint) private var tint

    private var name: String {
        category.map { String(localized: $0.label) } ?? String(localized: .categoryUncategorised)
    }

    private var amount: String { total.formatted(currencyCode: currencyCode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: category?.systemName ?? "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(name)
                    .font(.subheadline)

                Spacer(minLength: 12)

                Text(amount)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // A capsule in a `GeometryReader`-free layout: the track is the full
            // width and the fill is a fraction of it, so nothing has to measure
            // anything. `.frame(height:)` on the stack keeps the reader from
            // stretching the row.
            GeometryReader { proxy in
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(0, proxy.size.width * fraction))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .leading) {
                        Capsule().fill(.fill.quaternary)
                    }
            }
            .frame(height: 4)
        }
        // One element, one sentence. Read child by child this is a glyph, a
        // word, a figure and an unlabelled bar — where the bar is the one part
        // with nothing to say out loud.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(amount)")
    }
}
