/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

/// The payments that square the group up, and the two ways to log one.
struct SettleUpSection: View {
    let contents: GroupContents
    let currencyCode: String
    /// Which member is the person holding this phone, so a payment they owe
    /// reads in the first person.
    let me: Person?
    /// Logs the whole transfer as paid.
    let onSettle: (Transfer) -> Void
    /// Opens the sheet for handing over less than the whole of it.
    let onPartial: (Transfer) -> Void

    var body: some View {
        if !contents.transfers.isEmpty {
            Section {
                ForEach(contents.transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        currencyCode: currencyCode,
                        isMe: transfer.from.id == me?.id,
                        onSettle: { onSettle(transfer) },
                        onPartial: { onPartial(transfer) }
                    )
                }
            } header: {
                Text(.settleUp)
            } footer: {
                // Deliberately not "the fewest payments" — the calculator is
                // greedy, and the true minimum is NP-hard. See
                // `SettlementCalculator.transfers(settling:)`.
                Text(.settlementExplanation)
            }
        }
    }
}
