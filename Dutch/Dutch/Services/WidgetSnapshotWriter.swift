/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit
import Foundation
import WidgetKit

/// Keeps the Home Screen widget's copy of the balances current.
///
/// The widget never opens the database — see `WidgetSnapshot` for why — so this
/// is the only way anything reaches it. Rewritten on the same two triggers as
/// `SpotlightIndexer`, for the same reason: a group created here produces a save
/// and never a remote change, and an expense added on someone else's phone
/// produces a remote change and never a save. Watching one would leave the
/// widget showing yesterday's balance for exactly the case it exists for.
///
/// Also on identity changes, because touching and holding your own name changes
/// every figure the widget shows without touching the store at all.
///
/// The widget is only told to reload when the snapshot actually differs. WidgetKit
/// budgets reloads, and a sync delivers a burst of remote changes that mostly
/// alter nothing on the Home Screen.
@MainActor
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// Matches `SpotlightIndexer`: one CloudKit pull arrives as a run of
    /// notifications, and one write at the end of it is enough.
    private static let coalescingDelay = Duration.milliseconds(500)

    private var context: NSManagedObjectContext?
    private var pending: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var lastWritten: WidgetSnapshot?

    private init() {}

    /// Where the widget reads from: the shared app group, the only place a
    /// second process can see. `nil` without the entitlement, in which case
    /// there is no widget that could read it either, and nothing is written.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PersistenceController.appGroupIdentifier)?
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    /// Starts watching and writes what is there now.
    ///
    /// Not under `-uitesting-reset`: the UI tests run on a throwaway store, and
    /// their fixtures must not end up on the device's real Home Screen. The
    /// exception is a debug screenshot run, whose seeded store is exactly what
    /// the widget's App Store screenshot has to show.
    func start(reading context: NSManagedObjectContext) {
        guard observers.isEmpty else { return }
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        let isScreenshotRun = arguments.contains("-screenshots")
        #else
        let isScreenshotRun = false
        #endif
        guard !arguments.contains("-uitesting-reset") || isScreenshotRun else { return }

        self.context = context
        for name in [Notification.Name.NSManagedObjectContextDidSave,
                     .NSPersistentStoreRemoteChange,
                     ExpenseDefaults.identityDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { @MainActor in WidgetSnapshotWriter.shared.scheduleWrite() }
            })
        }
        scheduleWrite()
    }

    /// For the moments nothing posts a notification — leaving the app, which is
    /// when the last group opened is settled.
    ///
    /// Immediate rather than coalesced. iOS suspends the app as it leaves the
    /// screen, and a write waiting out the half-second delay simply never ran:
    /// the widget kept leading with the previous trip until the next launch.
    /// The file is a few kilobytes, so writing on the spot costs nothing.
    func refresh() {
        guard context != nil else { return }
        pending?.cancel()
        write()
    }

    private func scheduleWrite() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled else { return }
            self?.write()
        }
    }

    private func write() {
        guard let context, let url = Self.fileURL else { return }

        let snapshot = WidgetSnapshot(
            groups: GroupLookup.all(in: context)
                .filter { !$0.isArchived }
                .compactMap(Self.snapshot),
            lastOpenedGroupID: ExpenseDefaults.lastOpenedGroupID
        )
        guard snapshot != lastWritten else { return }

        do {
            try snapshot.write(to: url)
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // The widget keeps its previous figures, and the next save or sync
            // tries again. Nothing the person holding the phone could act on.
            print("[Dutch] Widget snapshot failed: \(error.localizedDescription)")
        }
    }

    /// `nil` for a group too incomplete to name, as everywhere else that lists
    /// groups outside the app.
    private static func snapshot(of group: ExpenseGroup) -> WidgetSnapshot.Group? {
        guard let id = group.id, let name = group.name else { return nil }

        let settlement = group.settlement()
        let members = Array((group.members as? Set<Person>) ?? [])
        // A member with no balance in the settlement is even, not unknown —
        // the same reading `Standing(balance:)` makes.
        let myBalance = ExpenseDefaults.me(in: group, among: members)?.id.map {
            settlement.balanceByParticipant[$0]?.cents ?? 0
        }

        return WidgetSnapshot.Group(
            id: id,
            name: name,
            currencyCode: group.currency,
            symbolName: group.appearance.symbol.systemName,
            colorName: group.appearance.color.rawValue,
            totalSpentCents: settlement.totalSpent.cents,
            myBalanceCents: myBalance,
            pendingTransfers: settlement.transfers.count
        )
    }
}
