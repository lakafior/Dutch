//
//  SceneDelegate.swift
//  Dutch
//
//  Created by Aditya Mishra on 23/09/26.
//

import UIKit
import CloudKit


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
