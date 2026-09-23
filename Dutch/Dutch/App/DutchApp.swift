/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents
import CloudKit
import SwiftUI
import UIKit

@main
struct DutchApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @Environment(\.scenePhase) private var scenePhase

    private let persistenceController = PersistenceController.shared

    init() {
        // Tells the system what this app's shortcuts take as parameters, so
        // the group picker in Shortcuts and Siri is populated rather than
        // empty. Cheap, and it has to happen before anything can run one.
        DutchShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                // Asked once per launch, and on every return from the
                // background, because signing out of iCloud does not restart
                // the app: without the second case a member stays badged "You"
                // for whoever picks the phone up next. See `CloudIdentity`.
                .task { await CloudIdentity.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await CloudIdentity.refresh() }
                        // For the same reason, and with a sharper edge: the
                        // settings screen's only remedy for a denied permission
                        // is a link into Settings.app, so returning from the
                        // background is precisely when the answer has changed.
                        // Without this the app would still believe it was
                        // refused, and the toggle the user had just come back
                        // to flip would stay disabled.
                        Task { await ExpenseNotifier.shared.refreshAuthorization() }
                    }
                }
        }
        // On the way to the background, not on the way in: the group the user
        // was last in is only settled once they stop looking at it, and
        // rewriting the quick action mid-session would change the Home Screen
        // under a menu somebody might have open.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { refreshQuickActions() }
        }
    }

    /// Names the Home Screen quick action after the group it will open.
    ///
    /// "New Expense · Berlin Trip" says what the long-press will actually do,
    /// which matters because it does something different depending on where the
    /// user was last.
    ///
    /// This is the *only* place the quick action is defined. There is no static
    /// twin in `Dutch-Info.plist`, because the system shows the static list and
    /// the dynamic one together — `shortcutItems` is the dynamic list alone and
    /// never replaces the plist. Defining both put two identical "New Expense"
    /// rows in the menu.
    ///
    /// Written unconditionally, including with no group: a deleted group would
    /// otherwise keep its name on the Home Screen, pointing at nothing.
    @MainActor
    private func refreshQuickActions() {
        let name = GroupLookup
            .lastOpened(in: persistenceController.viewContext)?
            .name

        UIApplication.shared.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickAction.newExpense,
                localizedTitle: String(localized: "New Expense"),
                localizedSubtitle: name,
                icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
                userInfo: nil
            )
        ]
    }
}

// MARK: - Quick Actions

/// The Home Screen quick action types, shared between the plist and the code
/// that handles them.
///
/// A mistyped identifier here is a long-press that does nothing at all, with no
/// error anywhere — so the string exists once.
enum QuickAction {
    /// Must match `UIApplicationShortcutItemType` in `Dutch-Info.plist`.
    static let newExpense = "net.smigi.Dutch.newExpense"

    /// Routes an activated quick action, if it is one this app knows.
    ///
    /// Falls through to the last opened group, exactly as `NewExpenseIntent`
    /// does — the two are the same action reached two ways, and they must not
    /// disagree about which group that means.
    @MainActor
    static func handle(_ item: UIApplicationShortcutItem) {
        guard item.type == newExpense else { return }
        AppRouter.shared.open(ExpenseDefaults.lastOpenedGroupID.map { .newExpense(in: $0) })
    }
}


