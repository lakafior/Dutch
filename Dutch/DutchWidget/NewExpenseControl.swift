/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center and Lock Screen button that opens a new expense.
///
/// Opens the form rather than adding anything directly. An expense is an amount,
/// a payer and a split, and a control has no way to ask for any of them; the
/// friction worth removing is the taps it takes to reach the form, not the form.
@available(iOS 18.0, *)
struct NewExpenseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "net.smigi.Dutch.NewExpenseControl") {
            ControlWidgetButton(action: OpenNewExpenseIntent()) {
                Label("New Expense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("New Expense")
        .description("Opens Dutch on a new expense in the group you opened last.")
    }
}
