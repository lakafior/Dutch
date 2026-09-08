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

// MARK: - App Delegate

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit delivers sync notifications silently; without registering,
        // the app only picks up remote changes on the next launch.
        application.registerForRemoteNotifications()

        // Starts publishing the groups to Spotlight and watching for changes.
        // Here rather than in `DutchApp.init` because it needs a loaded store,
        // and because this is already where launch-time registration lives.
        MainActor.assumeIsolated {
            SpotlightIndexer.shared.start(reading: PersistenceController.shared.viewContext)

            // Must be before launch finishes, not merely early: a notification
            // tapped while the app was not running is delivered as part of
            // launch, and a `UNUserNotificationCenter` delegate assigned any
            // later never hears about it. See `ExpenseNotifier.start`.
            ExpenseNotifier.shared.start()
        }

        return true
    }

    /// Holds the process open while the import a silent push triggered runs.
    ///
    /// The container handles the push itself and needs nothing from here — but
    /// without an implementation of this method the app has no background
    /// execution assertion, so iOS suspends it again the moment the push is
    /// delivered and the import finishes on some later launch instead. That is
    /// invisible while the only consumer of an import is the UI, and fatal to
    /// `ExpenseNotifier`, which exists to say something while nobody is
    /// looking at the UI.
    ///
    /// The completion handler must be called, and is, on both paths.
    ///
    /// The completion-handler form rather than the `async` one, and
    /// `nonisolated`, so that the untyped `userInfo` — which this reads nothing
    /// from, because the container owns the push's contents — is never sent
    /// across an actor boundary. The `async` spelling of the same method makes
    /// exactly that crossing, and is a hard error under Swift 6.
    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            let result = await ExpenseNotifier.shared.handleRemotePush()
            await MainActor.run { completionHandler(result) }
        }
    }

    /// Routes scene creation through `SceneDelegate` so share invitations can
    /// be handled — see the note there.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

// MARK: - Scene Delegate

/// Handles accepted CloudKit share invitations, Home Screen quick actions and
/// tapped Spotlight results.
///
/// This has to live on the *scene* delegate. The `UIApplicationDelegate`
/// equivalent is never called in a scene-based app, which is a quiet way to end
/// up with invitations that appear to do nothing when tapped.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            do {
                try await CloudSharingService.acceptShare(cloudKitShareMetadata)
            } catch {
                print("[Dutch] Failed to accept share: \(error.localizedDescription)")
            }
        }
    }

    /// A quick action tapped while the app was already running.
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        MainActor.assumeIsolated { QuickAction.handle(shortcutItem) }
        completionHandler(true)
    }

    /// A Spotlight result tapped while the app was already running.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        MainActor.assumeIsolated { SpotlightIndexer.handle(userActivity) }
    }

    /// A quick action or Spotlight result that launched the app.
    ///
    /// Both paths are needed, for each of them. The system delivers a
    /// cold-launch action here and never calls the matching method above for
    /// it, so handling only those gives a quick action — or a search result —
    /// that works until you actually quit the app.
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        MainActor.assumeIsolated {
            if let item = connectionOptions.shortcutItem {
                QuickAction.handle(item)
            }
            for activity in connectionOptions.userActivities {
                SpotlightIndexer.handle(activity)
            }
            restoreLastGroup()
        }
    }

    /// Opens the group the user was last in, if they asked for that and nothing
    /// else has already claimed the launch.
    ///
    /// **Last, and only into an empty destination.** A quick action, a Spotlight
    /// result or an intent each name a group out loud; this one is a default.
    /// A default that overrode an explicit destination would drop somebody into
    /// yesterday's trip instead of the thing they just tapped.
    ///
    /// Accepting an invitation is the case worth stating, because it is the one
    /// the setting could plausibly ruin. It doesn't: acceptance is asynchronous
    /// and never writes to the router at all — the group arrives by sync — and
    /// a first-time member has no last-opened group for this to restore. What
    /// is left is an existing user accepting a second invitation, who lands in
    /// their own last group with the list one tap behind them.
    ///
    /// Resolved through `GroupLookup` rather than handed to the router as a raw
    /// id, so a group deleted on another device simply does nothing here.
    /// `followRouter` answers an unresolvable id with an error banner, which is
    /// right for a tap and wrong for a launch nobody asked a question with.
    ///
    /// **Cold launch only, and deliberately.** This is called from
    /// `willConnectTo`, which runs when a scene *connects* — so returning from
    /// the background does not restore anything, and the app comes back to
    /// whatever was on screen. Moving this to a `scenePhase` hook to make it
    /// fire more often is the obvious next thought and it is wrong: a resume
    /// already returns you to the group you were in, because the navigation
    /// path is still in memory. The only thing a foreground restore could
    /// change is the case where you had deliberately navigated *back to the
    /// list* — and `lastOpenedGroupID` is never cleared when you do that (the
    /// quick action and Siri both need it to keep meaning "the trip I'm on"),
    /// so it would become impossible to stay on the group list across a
    /// backgrounding. Chosen 2026-08-28 over a time-thresholded resume.
    @MainActor
    private func restoreLastGroup() {
        guard AppRouter.shared.destination == nil, ExpenseDefaults.reopensLastGroup else {
            return
        }
        let context = PersistenceController.shared.viewContext
        AppRouter.shared.open(GroupLookup.lastOpened(in: context)?.id.map { .group($0) })
    }
}
