/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents

/// The Control Center and Lock Screen button: open Dutch on a new expense in the
/// group last opened.
///
/// Compiled into **both** the app and the widget extension, which is the one
/// thing about it that is easy to undo by accident. A control names its intent
/// by type, so the extension needs the type to build; and because the intent
/// opens the app, the system runs `perform()` in the app's process — where the
/// type also has to exist. Remove it from either target and the control either
/// fails to build or silently does nothing when pressed.
///
/// `NewExpenseIntent` is not reused because everything it touches — the store,
/// `AppRouter` — is app-only and would drag the app's model into the extension.
/// This one carries no parameter and resolves the group the way the Home Screen
/// quick action does.
struct OpenNewExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "New Expense" }

    static var description: IntentDescription {
        IntentDescription("Opens Dutch on a new expense in the group you opened last.")
    }

    /// Deprecated in iOS 26 in favour of `supportedModes`, which needs a
    /// deployment target this app doesn't have — as in `NewExpenseIntent`.
    static var openAppWhenRun: Bool { true }

    /// Hidden from Shortcuts, which already offers `NewExpenseIntent` under the
    /// same name with a group parameter. Two indistinguishable "New Expense"
    /// actions would be one too many.
    static var isDiscoverable: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        // Falls through to a plain launch on a phone with no group yet, which
        // opens the group list — exactly as the quick action does.
        AppRouter.shared.open(ExpenseDefaults.lastOpenedGroupID.map { .newExpense(in: $0) })
        #endif
        return .result()
    }
}
