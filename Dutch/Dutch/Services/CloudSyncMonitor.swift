/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import CoreData
import Foundation

/// What CloudKit mirroring is doing, when it last brought something down, and
/// why it stopped if it did.
///
/// **This cannot force a sync, and nothing in iOS can.**
/// `NSPersistentCloudKitContainer` decides for itself when to talk to the
/// server — at launch, on a silent push, and on its own schedule — and exposes
/// no "fetch now". So pull-to-refresh here is not a fetch. It is three things
/// that are worth having anyway:
///
/// - it **waits out** whatever sync is already in flight, so the spinner is on
///   screen for exactly as long as the app is genuinely busy rather than for a
///   fixed pretend interval;
/// - it **re-reads the store**, advancing the view context's pinned query
///   generation — see `PersistenceController.init`. That is the one staleness
///   this app can actually fix on demand: rows mirroring has already committed
///   that the on-screen snapshot predates;
/// - it **reports failures**, which until now only reached a `print`. Somebody
///   signed out of iCloud, or over quota, saw an app that had quietly stopped
///   sharing and said nothing about it. That is the real bug this fixes.
///
/// Anything claiming otherwise would be a lie told by the UI, so the copy in
/// `SyncStatusIndicator` says "synced", never "up to date".
@MainActor
@Observable
final class CloudSyncMonitor {
    static let shared = CloudSyncMonitor(controller: .shared)

    /// Whether the container has a setup, import or export in flight.
    private(set) var isSyncing = false

    /// When an import last finished successfully.
    ///
    /// Persisted, because the question it answers — when did data last come
    /// down from iCloud — is about the device and not about this launch. Left
    /// in memory it would read "Waiting for iCloud" for the first seconds of
    /// every cold launch, which is the moment somebody opening the app after a
    /// weekend away is most likely to be looking, and is indistinguishable on
    /// screen from sync being broken.
    ///
    /// In the app group suite rather than `.standard` so the widget on the
    /// roadmap can say the same thing without a stack of its own.
    ///
    /// Persisted by `record`, its only writer, rather than by a `didSet`.
    /// `@Observable` rewrites a tracked stored property into a computed one, so
    /// a property observer on it is not something the macro can carry — and the
    /// write has to survive, or the "Waiting for iCloud" cold-launch flash this
    /// property exists to prevent comes back.
    private(set) var lastSync: Date?

    /// The most recent failure, in words somebody can act on, or `nil` while
    /// everything is working.
    private(set) var problem: String?

    /// Whether there is any mirroring to report on at all. False for the
    /// in-memory store used by tests and previews, where the status footer
    /// would otherwise sit there permanently claiming iCloud was unreachable.
    let isEnabled: Bool

    /// How long the spinner stays up even when there was nothing to wait for.
    ///
    /// A pull that snaps back instantly reads as a gesture the app ignored,
    /// which is worse than one that visibly did a little work.
    private static let minimumVisibleDuration = Duration.milliseconds(600)

    /// How long to wait on an in-flight sync before giving up on it. Long
    /// enough for a first import on a real connection; short enough that a
    /// stalled one still ends the pull.
    private static let settleTimeout = Duration.seconds(12)

    private static let lastSyncKey = "cloudSync.lastImport"

    private let controller: PersistenceController
    private let defaults: UserDefaults

    /// Bookkeeping, not view state. `@Observable` tracks every stored `var` it
    /// is not told to leave alone, and nothing below is read from a body.
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// Identifiers of events that have started and not yet ended.
    @ObservationIgnored private var inFlight: Set<UUID> = []

    /// The last failure per kind of event, so a successful import clears the
    /// import's complaint without also clearing an export that is still failing
    /// — a full iCloud account can read fine and refuse every write.
    @ObservationIgnored
    private var problems: [NSPersistentCloudKitContainer.EventType: String] = [:]

    init(
        controller: PersistenceController,
        defaults: UserDefaults = PersistenceController.appGroupDefaults
    ) {
        self.controller = controller
        self.defaults = defaults
        self.isEnabled = controller.isCloudSyncEnabled

        guard isEnabled else { return }

        lastSync = defaults.object(forKey: Self.lastSyncKey) as? Date

        // Delivered on the main queue so the observed properties are written
        // where they are read. The event carries its own start and end, so this
        // is the whole of the bookkeeping.
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: controller.container,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }

            MainActor.assumeIsolated { self?.record(event) }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Refreshing

    /// Backs the pull-to-refresh gesture. See the note on the type for what it
    /// does and does not do.
    func refresh() async {
        let started = ContinuousClock.now

        await settle()
        reread()

        let elapsed = ContinuousClock.now - started
        if elapsed < Self.minimumVisibleDuration {
            try? await Task.sleep(for: Self.minimumVisibleDuration - elapsed)
        }
    }

    /// Waits for the in-flight events to finish, or for the timeout.
    ///
    /// Polled rather than awaiting a continuation resumed from `record`: this
    /// wait has to be abandonable, and a continuation that both the timeout and
    /// a late-arriving event can resume is a crash rather than a bug you can
    /// see. A tick every 100ms for at most a few seconds costs nothing.
    private func settle() async {
        let deadline = ContinuousClock.now + Self.settleTimeout

        while !inFlight.isEmpty, ContinuousClock.now < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Moves the view context onto whatever mirroring has committed since.
    ///
    /// The context is pinned to a query generation so that a merge arriving
    /// mid-read can't surface half-applied state, which also means it holds its
    /// snapshot until something advances it. Advancing it here is the part of
    /// the pull that genuinely changes what is on screen.
    ///
    /// `refreshAllObjects` then faults the cached rows so the next fetch reads
    /// the store rather than the row cache. It leaves objects with unsaved
    /// changes alone, so an expense being edited in a sheet is safe.
    private func reread() {
        let context = controller.viewContext
        try? context.setQueryGenerationFrom(.current)
        context.refreshAllObjects()
    }

    // MARK: - Events

    private func record(_ event: NSPersistentCloudKitContainer.Event) {
        guard let ended = event.endDate else {
            inFlight.insert(event.identifier)
            isSyncing = true
            return
        }

        inFlight.remove(event.identifier)
        isSyncing = !inFlight.isEmpty

        if event.succeeded {
            problems[event.type] = nil
            // Only an import can have brought something new down. A successful
            // export means this device's changes left, which is not what
            // "synced" is being read to mean on the group list.
            // Persisted here rather than in a property observer — see `lastSync`.
            // Guarded on a change for the reason the old `didSet` was: an
            // import that brought nothing new down should not rewrite the key.
            if event.type == .import, lastSync != ended {
                lastSync = ended
                defaults.set(ended, forKey: Self.lastSyncKey)
            }
        } else {
            problems[event.type] = event.error.map(Self.describe)
                ?? String(localized: "iCloud sync didn't finish.")
        }

        // Import first: it is the half the person staring at a group somebody
        // else edited actually cares about.
        problem = problems[.import] ?? problems[.export] ?? problems[.setup]
    }

    /// Turns a CloudKit failure into a sentence worth putting on screen.
    ///
    /// `localizedDescription` alone is not usable here — it says things like
    /// "Failed to modify some record zones", which tells somebody whose iCloud
    /// is full nothing about why their group stopped updating.
    ///
    /// `nonisolated` so it can be exercised without a main-actor hop; it reads
    /// nothing but its argument.
    nonisolated static func describe(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        switch ckError.code {
        case .notAuthenticated:
            return String(localized: "Sign in to iCloud in Settings to sync your groups.")
        case .quotaExceeded:
            return String(localized: "Your iCloud storage is full, so changes aren't syncing.")
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return String(localized: "iCloud is unreachable. Changes will sync when the connection is back.")
        case .managedAccountRestricted, .permissionFailure:
            return String(localized: "This Apple Account isn't allowed to sync with iCloud.")
        case .zoneNotFound, .userDeletedZone:
            return String(localized: "This group is no longer in iCloud.")
        case .partialFailure:
            // The umbrella error describes nothing; the reason is on one of the
            // items underneath it. CloudKit does not nest these, so taking the
            // first one is a single step down rather than a recursion.
            if let underlying = ckError.partialErrorsByItemID?.values.first {
                return describe(underlying)
            }
            return "Some changes couldn't be synced with iCloud."
        default:
            return ckError.localizedDescription
        }
    }
}
