/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// What the Home Screen widget shows, written by the app and read by the widget.
///
/// A file of plain values rather than a second Core Data stack in the widget's
/// process. The stores mirror to CloudKit, and two processes running
/// `NSPersistentCloudKitContainer` over the same files would both try to sync
/// them. The widget would also pay for Core Data, the model and the settlement
/// on every refresh to compute a number the app has already computed. So the app
/// does the arithmetic once, on every save and every sync, and the widget draws
/// what it is handed.
///
/// Every amount is a balance as the app already reports it — no settlement logic
/// lives on the widget side to disagree with the group list.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// One group, as a row in the widget.
    public struct Group: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let name: String
        public let currencyCode: String
        /// An SF Symbol name — the group's emblem.
        public let symbolName: String
        /// A palette name such as `teal`, resolved to a colour by the widget.
        public let colorName: String
        /// What the group has spent in total, in minor units.
        public let totalSpentCents: Int
        /// The device owner's net position in minor units: positive when they
        /// are owed, negative when they owe. `nil` when the device hasn't been
        /// told which member it belongs to — there is then no "you" to report,
        /// and the widget falls back to the total, as the group list does.
        public let myBalanceCents: Int?
        /// Payments still needed to square the whole group.
        public let pendingTransfers: Int

        public init(
            id: UUID, name: String, currencyCode: String, symbolName: String, colorName: String,
            totalSpentCents: Int, myBalanceCents: Int?, pendingTransfers: Int
        ) {
            self.id = id
            self.name = name
            self.currencyCode = currencyCode
            self.symbolName = symbolName
            self.colorName = colorName
            self.totalSpentCents = totalSpentCents
            self.myBalanceCents = myBalanceCents
            self.pendingTransfers = pendingTransfers
        }

        public var totalSpent: Money { Money(cents: totalSpentCents) }
        public var myBalance: Money? { myBalanceCents.map(Money.init(cents:)) }
    }

    /// Active groups, newest first — the group list's order. Archived groups are
    /// left out: a finished trip has no business on the Home Screen.
    public let groups: [Group]
    /// The group opened most recently in the app, which is the trip somebody is
    /// on — the same answer the Home Screen quick action and Siri use.
    public let lastOpenedGroupID: UUID?

    public init(groups: [Group], lastOpenedGroupID: UUID?) {
        self.groups = groups
        self.lastOpenedGroupID = lastOpenedGroupID
    }

    public static let empty = WidgetSnapshot(groups: [], lastOpenedGroupID: nil)

    /// The groups to show, the featured one first.
    ///
    /// The last group opened leads, because that is the trip somebody is on; the
    /// rest follow in list order. A last-opened id that no longer matches an
    /// active group — archived, deleted, or left — is ignored rather than
    /// trusted, so the widget never leads with a trip that isn't on the list.
    public func ordered(limit: Int) -> [Group] {
        guard limit > 0 else { return [] }
        let featured = groups.first { $0.id == lastOpenedGroupID }
        let rest = groups.filter { $0.id != featured?.id }
        return Array(([featured].compactMap { $0 } + rest).prefix(limit))
    }

    // MARK: - Storage

    /// The file's name inside the shared app group container.
    public static let fileName = "widget-snapshot.json"

    /// Reads a snapshot, or `empty` when there is none yet or it can't be
    /// decoded. A widget with nothing to show says so; it never crashes over a
    /// file written by a newer or older build of the app.
    public static func read(from url: URL) -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    /// Writes atomically, so the widget can never read half a file.
    public func write(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
