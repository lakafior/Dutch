/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData

/// How many groups this device may *create* before the purchase is needed.
///
/// The rule counts created groups only. Joining is free and always unlimited,
/// and that asymmetry is the whole design rather than a concession:
///
/// The app spreads by someone at a dinner table saying "install this and scan
/// the code". The person scanning didn't choose the app, isn't the one who will
/// still be using it in three months, and is standing in front of five people
/// waiting on them. Charging them — or charging them *later*, on their second
/// invitation, which is what counting joined groups would amount to — puts a
/// paywall at the single worst moment in the app's life and breaks the one
/// mechanism that gets it installed at all.
///
/// So the limit falls on the organiser: the person who creates trips, who gets
/// repeat value, and who is deciding at a keyboard rather than at a table.
///
/// A group's store is what tells the two apart, and it is a reliable signal
/// rather than a heuristic: `NSPersistentCloudKitContainer` puts groups this
/// user created in the private store and groups shared *with* them in the
/// shared one. An owner's copy of a group they later shared stays private, so
/// sharing a group never changes which side of this rule it falls on.
enum GroupLimit {
    /// Groups a device can create without the purchase.
    ///
    /// One is enough for the case the app was built for — a trip, a dinner, one
    /// group of people — so the free tier is a complete app rather than a demo.
    static let freeCreatedGroups = 1

    /// Whether this group arrived from someone else's invitation.
    static func isJoined(_ group: ExpenseGroup) -> Bool {
        group.objectID.persistentStore?.url?.lastPathComponent
            == PersistenceController.sharedStoreFilename
    }

    /// Archived groups still count, deliberately.
    ///
    /// The rule is on groups *created*, and archiving is a change to a list
    /// rather than to what was created. Discounting them would also make the
    /// limit trivially bypassable — archive, create, unarchive — which is the
    /// kind of hole that is found within a week of shipping. So the caller must
    /// pass every group it has, not the filtered list it is drawing:
    /// `GroupListView` fetches unfiltered for exactly this reason and splits
    /// for display only.
    static func createdCount(among groups: some Sequence<ExpenseGroup>) -> Int {
        groups.lazy.filter { !isJoined($0) }.count
    }

    /// Whether another group can be created.
    ///
    /// `unlocked` comes from `PurchaseStore.hasUnlimitedGroups` and is passed in
    /// rather than read here, so the rule can be tested without StoreKit.
    static func canCreate(
        among groups: some Sequence<ExpenseGroup>,
        unlocked: Bool
    ) -> Bool {
        unlocked || createdCount(among: groups) < freeCreatedGroups
    }
}
