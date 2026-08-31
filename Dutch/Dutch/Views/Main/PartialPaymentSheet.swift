/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import DutchKit

/// Sheet for logging part of a suggested payment.
///
/// *A owes B 1000, and B wants it in five instalments of 200.* The store has
/// always been able to write that — `GroupStore.recordPayment` takes any
/// `Money` and compares it to nothing — so this sheet is the whole of the
/// feature: `TransferRow` used to hand the button the entire transfer and had
/// no way to offer less.
///
/// **It records a payment; it does not create a plan.** The settlement is
/// recomputed from balances on every render and cannot remember that a row was
/// half paid, because there are no rows to remember. With two people that is
/// invisible: 1000 becomes 800 and the list says what the user expects. With
/// two on each side the pairing can legitimately change under them — every
/// figure still correct, but the row somebody was halfway through paying now
/// gone. Making the transfer list durable would fix the appearance by adding a
/// second source of truth for one fact, and the first time the two disagreed
/// the balances would be right while the plan was what the user was reading.
/// So five payments of 200 do clear the debt; the app simply never narrates
/// them as instalments.
struct PartialPaymentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let transfer: Transfer
    let currencyCode: String
    /// Whether the payment is one *this* device's owner has to make.
    let isMe: Bool
    let onRecord: (Money, Date) -> Void

    /// Prefilled with the whole transfer, for the inverse of the reason the
    /// duplicate form leaves the payer empty: there the blank field is the one
    /// that must be answered deliberately, and here the filled one is the
    /// entire point of the sheet — settling in full stays the common case, and
    /// arriving here by mistake costs a Cancel rather than a figure to type.
    @State private var amountText: String
    @FocusState private var amountFocused: Bool

    /// When the money changed hands. *"I paid her back last Tuesday"* is as
    /// ordinary a sentence as backdating a receipt, and a payment stamped today
    /// lands in the wrong day of the same log the expenses are filed in.
    ///
    /// Only here, never on **Mark Paid**. That button is the common case and
    /// has to stay one tap; somebody settling on a different day is already
    /// opening this sheet.
    @State private var date = Date()

    init(
        transfer: Transfer,
        currencyCode: String,
        isMe: Bool,
        onRecord: @escaping (Money, Date) -> Void
    ) {
        self.transfer = transfer
        self.currencyCode = currencyCode
        self.isMe = isMe
        self.onRecord = onRecord
        _amountText = State(initialValue: DecimalInput.text(transfer.amount.amount))
    }

    // MARK: - Derived

    private var payer: String {
        isMe ? String(localized: "You") : transfer.from.name
    }

    private var fullAmount: String {
        transfer.amount.formatted(currencyCode: currencyCode)
    }

    /// What was typed, as money. `nil` while the field is empty or not yet a
    /// figure above zero, which is one case for the confirm button.
    private var entered: Money? {
        DecimalInput.parse(amountText).map(Money.init(amount:))
    }

    /// Capped at the suggestion, which is the one place the precedents in this
    /// app disagree. Handing over 1200 against a debt of 1000 and taking change
    /// is ordinary behaviour at a table, and the maths needs no help with it —
    /// the recipient would owe 200 afterwards and the next render would say so.
    /// The cap wins on the reading that a figure above the suggestion is far
    /// more often a slipped decimal than an intention, the same argument that
    /// caps the tip. Anyone who genuinely means to overpay can overpay in cash
    /// and let the app describe what is left.
    private var isOverFull: Bool {
        guard let entered else { return false }
        return entered > transfer.amount
    }

    private var canRecord: Bool { entered != nil && !isOverFull }

    private var header: String {
        isMe
            ? String(localized: "You pay \(transfer.to.name)")
            : String(localized: "\(transfer.from.name) pays \(transfer.to.name)")
    }

    /// Says what the cap is *before* it is hit, so refusing a larger figure
    /// later reads as a rule that was stated rather than a control that broke.
    private var footer: String {
        isOverFull
            ? String(localized: "That is more than the \(fullAmount) outstanding.")
            : String(localized: "Up to \(fullAmount). Anything less leaves the rest owing.")
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        // Hidden from VoiceOver because the field carries the
                        // same label — otherwise it is announced twice.
                        Text("Amount Paid")
                            .accessibilityHidden(true)

                        Spacer(minLength: 12)

                        TextField("0", text: $amountText)
                            .focused($amountFocused)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            // The same key as the visible label, not a
                            // sentence-cased twin of it — one phrase should not
                            // reach a translator as two entries.
                            .accessibilityLabel("Amount Paid")
                            .accessibilityHint("In \(currencyCode)")

                        // Stands in for selecting the prefilled figure, which
                        // is what this sheet actually wants and what iOS 17
                        // gives no way to do — `TextField(text:selection:)` is
                        // iOS 18. Without it, overriding a four-digit default
                        // is four backspaces before a single digit is typed.
                        //
                        // Padded rather than framed to 44pt: a square that
                        // large in a form row crowds the figure it sits beside,
                        // and this matches the size of the system clear button
                        // every iOS text field already has.
                        if !amountText.isEmpty {
                            Button {
                                amountText = ""
                                amountFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.borderless)
                            .padding(.leading, 8)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Clear amount")
                        }

                        Text(currencyCode)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    // Bounded at today for the same reason the expense form is:
                    // a payment is something that happened, and the error worth
                    // catching is the fat-fingered year. No `max` against a
                    // seeded value here — this record is always new, so there is
                    // no stored date that could already sit outside the range.
                    //
                    // A step down in weight, matching what `ExpenseFormView`
                    // does to every row it can be saved without. The sheet has
                    // exactly two rows and only one of them is the point; drawn
                    // level, they would read as two equal questions.
                    DatePicker(
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .date
                    ) {
                        Text("Date")
                    }
                    .datePickerStyle(.compact)
                    .font(.subheadline)
                    .controlSize(.small)
                } header: {
                    Text(header)
                } footer: {
                    Text(footer)
                }
            }
            .navigationTitle(Text(.settleUp))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record Payment", action: record)
                        .disabled(!canRecord)
                }
            }
        }
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
        .task { amountFocused = true }
    }

    private func record() {
        guard let entered, !isOverFull else { return }
        onRecord(entered, date)
        dismiss()
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            PartialPaymentSheet(
                transfer: Transfer(
                    from: Participant(id: UUID(), name: "Anna"),
                    to: Participant(id: UUID(), name: "Bob"),
                    amount: Money(amount: 1000)
                ),
                currencyCode: "USD",
                isMe: true
            ) { amount, date in print("record \(amount) on \(date)") }
        }
}
