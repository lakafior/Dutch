/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import WidgetKit

/// Everything the extension offers: the balance widget, and on iOS 18 the
/// "New Expense" control for Control Center and the Lock Screen.
///
/// The control is gated rather than raising the extension's deployment target:
/// controls only exist from iOS 18, and an iOS 17 phone should still get the
/// widget rather than nothing.
@main
struct DutchWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        if #available(iOS 18.0, *) {
            NewExpenseControl()
        }
    }
}
