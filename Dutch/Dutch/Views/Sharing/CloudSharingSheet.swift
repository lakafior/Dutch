/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import SwiftUI
import UIKit

// MARK: - SwiftUI presentation

/// Presents the system sharing UI for a group.
///
/// `UICloudSharingController` has no SwiftUI equivalent, so it is bridged here.
///
/// This is the **management** screen, not the invitation one. Its customisation
/// surface is four properties — `availablePermissions` and three delegate
/// methods — so the participant list, the access picker and **Stop Sharing**
/// cannot be hidden, reordered or restyled. Since sending a link no longer goes
/// through here (`ShareGroupView` uses `ShareLink` on the share URL, which works
/// because the share is open to anyone holding it), the only reasons left to
/// present this sheet are the destructive ones: removing a participant, or
/// closing the group to new members. `ShareGroupView` shows it to the owner
/// only, one level down, for exactly that reason.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    /// The share as CloudKit saved it, after the owner changed something here.
    ///
    /// Without this the caller keeps rendering the `CKShare` it captured before
    /// presenting, so a group switched to invitation-only goes on claiming its
    /// QR code works until the screen is closed and reopened.
    var onSaveShare: (CKShare) -> Void = { _ in }

    /// The owner tapped **Stop Sharing**.
    ///
    /// This is the authoritative signal, and it has to be a callback rather than
    /// something the caller reconciles on dismiss: the sheet deletes the
    /// `CKShare` through CloudKit directly, and Core Data's cached copy can
    /// still answer `fetchShares(matching:)` for a moment afterwards. Polling
    /// for the absence would sometimes see the share that was just deleted.
    var onStopSharing: () -> Void = {}

    /// CloudKit refused a change the owner made here.
    ///
    /// Worth surfacing rather than printing, because the sheet's own reporting
    /// is not dependable: when the failure is `NoAccountExists` the
    /// `com.apple.CloudSharingUI.CloudSharing` extension invalidates its remote
    /// view controller instead, so the sheet vanishes and this is never called.
    /// That is the one failure a person can diagnose unaided — they are signed
    /// out — and the ones that *do* arrive here (quota, network, an oplock
    /// conflict) are the ones that otherwise look like nothing happened.
    var onFailedToSave: (Error) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSaveShare: onSaveShare,
            onStopSharing: onStopSharing,
            onFailedToSave: onFailedToSave
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        // `.allowPublic` has to be here or the sheet won't show "Anyone with
        // the link" — and without that setting the group's QR code admits
        // nobody. `.allowPrivate` stays available so an owner who wants a
        // closed group can still switch back to invitation-only.
        //
        // `.allowReadOnly` is deliberately absent: a group whose members can't
        // add expenses is not a bill-splitting group, and the row collapses to
        // a single option rather than offering a setting that only breaks
        // things.
        controller.availablePermissions = [.allowReadWrite, .allowPublic, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let onSaveShare: (CKShare) -> Void
        private let onStopSharing: () -> Void
        private let onFailedToSave: (Error) -> Void

        init(
            onSaveShare: @escaping (CKShare) -> Void,
            onStopSharing: @escaping () -> Void,
            onFailedToSave: @escaping (Error) -> Void
        ) {
            self.onSaveShare = onSaveShare
            self.onStopSharing = onStopSharing
            self.onFailedToSave = onFailedToSave
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            print("[Dutch] Failed to save share: \(error.localizedDescription)")
            Task { @MainActor in onFailedToSave(error) }
        }

        /// Writes the sheet's edits back into the Core Data store.
        ///
        /// The sheet can change *who can access* — the owner may switch a group
        /// back to invitation-only — so this is not a no-op.
        /// `NSPersistentCloudKitContainer` doesn't observe changes made to a
        /// `CKShare` by CloudKit APIs, so without this the local cache keeps
        /// reporting the old permission and `makeScannable` would reopen a
        /// group the owner just closed.
        ///
        /// The private store is the right one because this sheet is only ever
        /// presented for a group the user owns — see `ShareGroupView`, which
        /// gates it on `GroupLimit.isJoined`.
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            Task { @MainActor in
                guard let store = PersistenceController.shared.privateStore else { return }
                do {
                    let saved = try await PersistenceController.shared.container
                        .persistUpdatedShare(share, in: store)
                    onSaveShare(saved)
                } catch {
                    print("[Dutch] Failed to persist updated share: \(error.localizedDescription)")
                    // The server took the change even though the mirror didn't,
                    // so report what the sheet has rather than nothing.
                    onSaveShare(share)
                }
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            print("[Dutch] Share stopped")
            Task { @MainActor in onStopSharing() }
        }
    }
}
