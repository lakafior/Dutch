//
//  AppDelegate.swift
//  Dutch
//
//  Created by Aditya Mishra on 23/09/26.
//

import UIKit


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
