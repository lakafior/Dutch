/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    /// The payer's avatar, so the colour that identifies them on the members
    /// list identifies their spending too — the log becomes scannable by whose
    /// it is before a word of it is read.
    ///
    /// Optional because `paidBy` is: an expense whose payer is mid-sync still
    /// has to draw a row, and `SettlementBridge` already drops it from the
    /// maths. It falls back to the grey no-name circle rather than to a gap,
    /// which would break the column the rest of the list lines up on.
    let avatar: PersonAvatar?
    let currencyCode: String

    /// The title, or `nil` for an expense saved without one.
    ///
    /// Blank and absent are the same thing here. `GroupStore` stores an empty
    /// title as `nil`, but a record synced from a client built before titles
    /// were optional can still carry `""` — and a row testing only for `nil`
    /// would draw an empty line for it.
    private var title: String? {
        let text = expense.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? nil : text
    }

    private var payer: String { expense.paidBy?.name ?? "?" }

    /// Where it happened, when that is not already what the row is called.
    ///
    /// Picking a place writes both the title and the place, so the ordinary
    /// case is that the two are the same string and this stays `nil` — drawing
    /// it then would print the café's name twice on one row. It reappears the
    /// moment somebody renames the expense to *Anna's birthday*, which is
    /// exactly when the place stops being readable off the title.
    private var place: String? {
        let text = expense.placeName?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !text.isEmpty else { return nil }
        return text.caseInsensitiveCompare(title ?? "") == .orderedSame ? nil : text
    }

    /// A pin beside the title when this expense is attached to a place.
    ///
    /// Without it an attached place leaves no trace on the row at all: picking
    /// writes the title *and* the place, so the two are usually the same string
    /// and `place` below deliberately draws nothing. That made opening the form
    /// the only way to find out whether an expense was pinned — which, for a
    /// fact that syncs to everyone in the group, is the wrong way round.
    ///
    /// A glyph and not the words, for the reason `categoryMark` is one: the row
    /// is scanned, and the words are usually already on it as the title.
    @ViewBuilder
    private var placeMark: some View {
        if expense.placeName?.isEmpty == false {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption2)
                .foregroundStyle(.secondary)
                // The row's own label already reads the place out where it
                // differs from the title; a second "pinned" would be a word
                // VoiceOver says on every such row for no new information.
                .accessibilityHidden(true)
        }
    }

    /// The second line: who paid, and where, when the two fit together.
    ///
    /// Joined onto the payer's line rather than given one of its own. This row
    /// went from three lines to two once the date moved into the day header,
    /// and a place is not worth undoing that for — it is a qualifier on a line
    /// that already reads as one.
    @ViewBuilder
    private var payerLine: some View {
        Group {
            if let place {
                Text("\(payer) · \(place)")
            } else {
                Text(payer)
            }
        }
        // `.secondary`, not `.tertiary`: tertiary is for decoration, and who
        // paid is the point of the row.
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityLabel(place.map { "\(accessiblePayer), \($0)" } ?? accessiblePayer)
    }

    /// VoiceOver gets no colour from the circle and would otherwise hear a bare
    /// name with nothing saying what it is doing there.
    private var accessiblePayer: String {
        String(
            localized: "Paid by \(expense.paidBy?.name ?? String(localized: "unknown"))",
            comment: "VoiceOver reading of who paid for an expense. The placeholder is a member name."
        )
    }

    /// The category glyph, drawn beside whatever leads the row.
    ///
    /// A glyph and not the word. The log is scanned rather than read, the row
    /// already spends its width on a title, a payer and two figures, and the
    /// form's menu is where the glyph is learned — it lists every category with
    /// its name beside it. Nothing is drawn at all for an unfiled expense: a
    /// placeholder tag in that column would make "no category" look like a
    /// category, and most expenses will never have one.
    ///
    /// `.secondary` and never tinted. Every colour in this list already belongs
    /// to a person or to a balance, and a third colour system competing with
    /// those is how a row stops being scannable.
    @ViewBuilder
    private var categoryMark: some View {
        if let category = expense.category {
            Image(systemName: category.systemName)
                // `.caption` first time round, which was too quiet to find: the
                // first person to use categories on real expenses reported not
                // being able to see them anywhere. Level with the title it sits
                // beside, still `.secondary` so it labels the row rather than
                // competing with it.
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Sized so a wide glyph and a narrow one leave the titles
                // beside them starting in the same place.
                .frame(width: 18)
                .accessibilityLabel(Text(category.label))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            PersonIcon(avatar ?? PersonAvatar(initials: nil, color: .gray), size: 26)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    HStack(spacing: 6) {
                        categoryMark
                        Text(title)
                            .font(.body)
                        placeMark
                    }

                    // Three lines once — title, date, "Paid by X". The date
                    // moved to the day header above and the circle carries the
                    // payer, which leaves the name as the one thing still worth
                    // a second line: initials are ambiguous and a colour has to
                    // be learned.
                    payerLine
                } else {
                    // An untitled expense leads with the payer rather than with
                    // a filler word. "Untitled" says nothing, and says it again
                    // on every row once titles are optional — where the payer
                    // and the amount together are already a complete sentence.
                    // `PaymentRow` in this same list has established that a
                    // one-line row reads fine among two-line ones.
                    HStack(spacing: 6) {
                        categoryMark
                        Text(payer)
                            .font(.body)
                            .accessibilityLabel(accessiblePayer)
                        placeMark
                    }

                    // Only ever drawn for an expense somebody stripped the
                    // title off while keeping the place, which is rare — and
                    // the one case where dropping it would lose the row's only
                    // remaining word about what this was.
                    if let place {
                        Text(place)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                    .font(.callout)
                    .monospacedDigit()

                // What was actually handed over, for expenses paid abroad. The
                // group's own figure stays the prominent one — it is the number
                // the balances are built from — with this as its receipt.
                if let foreign = expense.foreignAmount {
                    Text(foreign.formatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
