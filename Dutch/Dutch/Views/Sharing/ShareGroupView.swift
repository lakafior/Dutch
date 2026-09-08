/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import CoreData
import SwiftUI

/// Shows a group's invitation: a QR code carrying the CloudKit share URL, the
/// word sequence for confirming it out loud, and a plain link to send.
///
/// The QR encodes the **share URL**, not the word sequence. Without a server
/// there is nothing that could turn three words back into a group, so the words
/// are a label and the URL is the thing that actually grants access.
///
/// Two ways out of this screen and they are deliberately unequal. Scanning the
/// code and receiving the link are the same act — the share is open to whoever
/// holds the URL — so the primary button is a bare `ShareLink` with nothing
/// attached to it. `UICloudSharingController`, which used to be that button,
/// carries a participant list, an access picker and a **Stop Sharing** that
/// revokes the group for everyone; it now sits behind **Manage Access**, owner
/// only, below the fold. See `invitationAction` and `manageAccess`.
struct ShareGroupView: View {
    let group: ExpenseGroup

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .preparing
    /// Presents the *management* sheet, not an invitation. See `manageAccess`.
    @State private var showingManageAccess = false
    @State private var showingAppStoreCode = false
    /// A change the owner made in the management sheet that CloudKit refused.
    @State private var manageAccessError: String?
    /// Built on first disclosure rather than alongside the join code, because
    /// most invitations are shown to people who already have the app and would
    /// never pay for it. Cached here so collapsing and reopening is free.
    @State private var appStoreCode: UIImage?

    private enum Phase {
        case preparing
        /// The QR code is carried here rather than generated in `body`.
        /// Encoding a share URL at correction level Q and rasterising it to a
        /// `CGImage` is milliseconds of work, and `body` re-ran it on every
        /// state change — including the one that presents the invite sheet, so
        /// it landed squarely in that transition.
        case ready(share: CKShare, container: CKContainer, qrCode: UIImage?)
        case failed(String)
    }

    /// The App Store listing, encoded into the code somebody without Dutch
    /// scans.
    ///
    /// Deliberately Apple's own URL and not a link through `dutch.smigi.net`.
    /// A wrapper on our domain could have carried the share token as well and
    /// made one code do both jobs — but it would put a lapsed renewal or a
    /// misconfigured redirect between two people at a table and the group they
    /// are trying to join. Nothing about this invitation depends on
    /// infrastructure we own, and that is worth more than a second of the
    /// guest's time.
    ///
    /// The numeric id is the stable form: the slug in a listing URL follows the
    /// app's name, so it changes if the name ever does.
    private static let appStoreURL = URL(string: "https://apps.apple.com/app/id6795190862")

    #if DEBUG
    /// What the QR encodes in an App Store screenshot.
    ///
    /// Deliberately the marketing site and not a plausible-looking
    /// `icloud.com/share/…` string. A published screenshot's QR is *scannable*,
    /// so it will be scanned — by anybody who points a camera at the listing.
    /// A real share URL would hand them a working key to a real group, and a
    /// fake one wastes the scan on an error page. The site answers the question
    /// somebody scanning a screenshot of a bill-splitting app actually has.
    ///
    /// Verify every published capture still decodes to this and not to a live
    /// token: `swift Tools/qr.swift <file>`.
    private static let screenshotShareURL = URL(string: "https://dutch.smigi.net")
    #endif

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .preparing:
                    ProgressView("Preparing invitation…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready(let share, let container, let qrCode):
                    readyContent(share: share, container: container, qrCode: qrCode)

                case .failed(let message):
                    ContentUnavailableView(
                        "Can't Share This Group",
                        systemImage: "exclamationmark.icloud",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Share Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await prepareShare() }
    }

    // MARK: - Ready state

    @ViewBuilder
    private func readyContent(
        share: CKShare,
        container: CKContainer,
        qrCode: UIImage?
    ) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                if let qrCode {
                    Image(uiImage: qrCode)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 250, maxHeight: 250)
                        .padding(20)
                        // Deliberately white in both appearances, and not a
                        // semantic background: the generator emits black on
                        // white regardless of colour scheme, and a scanner
                        // needs that light quiet zone around the code. Swapping
                        // this for `systemBackground` would break scanning in
                        // dark mode while looking like a fix.
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .accessibilityLabel("QR code to join \(group.name ?? "this group")")
                } else {
                    ContentUnavailableView(
                        "Invitation Not Ready",
                        systemImage: "qrcode",
                        description: Text(.iCloudLinkCreationUnfinished)
                    )
                }

                if let sequence = group.wordSequence {
                    VStack(spacing: 8) {
                        // This is the confirmation channel — the thing two
                        // people read to each other to be sure they joined the
                        // same group — so it gets the weight of a heading
                        // rather than sitting a step below the QR caption.
                        Text(sequence)
                            .font(.title.weight(.semibold))
                            .monospaced()
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())

                        Text(.checkMatchOnOtherDevice)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                invitationAction(share: share)

                appStoreDisclosure(share: share)

                // Told from the share's real permission, not from what the app
                // asked for. A group made by an older build — or one the owner
                // switched back to invitation-only — still shows a QR code,
                // and that code admits nobody. Claiming otherwise would send
                // people to a scanner that can only fail.
                Group {
                    if share.publicPermission == .none {
                        Text(.qrInvitationInstructions)
                    } else {
                        // Scanning is joining, with no approval step on this
                        // device. That's the point — but it has to be said,
                        // because a QR code doesn't look like a key.
                        Text(.newAdditionInstructions)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

                // Last on the screen on purpose: everything above it is the
                // invitation, and this is the only control that can take one
                // away.
                manageAccess(share: share)
                    .padding(.bottom, 8)
            }
            .padding(.top, 24)
        }
        .sheet(isPresented: $showingManageAccess) {
            CloudSharingSheet(
                share: share,
                container: container,
                onSaveShare: refresh,
                onStopSharing: handleStopSharing,
                onFailedToSave: { manageAccessError = $0.localizedDescription }
            )
            .ignoresSafeArea()
        }
        .alert(
            "Couldn't Change Access",
            isPresented: .init(
                get: { manageAccessError != nil },
                set: { if !$0 { manageAccessError = nil } }
            ),
            presenting: manageAccessError
        ) { _ in
            Button("OK", role: .cancel) { manageAccessError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Sending an invitation

    /// Whether this group is ours to administer.
    ///
    /// A member who joined by invitation can still hand the link on — the share
    /// is open to anyone holding it, so passing it along is an ordinary thing to
    /// do at a table — but only the owner gets the management sheet.
    private var isOwner: Bool { !GroupLimit.isJoined(group) }

    /// The primary action: hand somebody the link.
    ///
    /// This deliberately does **not** go through `UICloudSharingController`. That
    /// sheet exists to add named participants so the URL will work for them, and
    /// `makeScannable` already made the URL work for everybody — so its whole
    /// contribution to an invitation is a screen carrying a participant list, an
    /// access picker and a **Stop Sharing** button that revokes the group for
    /// every member at once. `ShareLink` sends the same URL through Messages,
    /// Mail or AirDrop with none of that attached, and the recipient's join is
    /// identical to a scan.
    ///
    /// The exception is a group the owner closed to invitations. Its URL
    /// authorises nobody, so a link would be an invitation that cannot be
    /// accepted, and the system sheet — which adds the recipient as it sends —
    /// is the only thing that can invite at all. Non-owners get no button there,
    /// because they have nothing they could offer.
    @ViewBuilder
    private func invitationAction(share: CKShare) -> some View {
        if share.publicPermission == .none {
            if isOwner {
                Button {
                    showingManageAccess = true
                } label: {
                    Label("Invite People", systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }
        } else if let url = share.url {
            ShareLink(
                item: url,
                subject: Text(group.name ?? "Expense Group"),
                message: Text(invitationMessage)
            ) {
                Label("Send Link", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
        }
    }

    /// What a bare `icloud.com/share/…` URL looks like without it: spam.
    private var invitationMessage: String {
        let name = group.name ?? String(localized: "Expense Group")
        return String(localized: "Join \(name) on Dutch to split expenses together.")
    }

    // MARK: - Managing access

    /// The system sharing sheet, demoted to a destination.
    ///
    /// Everything destructive about sharing lives behind this one row: removing
    /// a participant, and **Stop Sharing**, which deletes the `CKShare` and takes
    /// the group off every member's device — their copy only ever mirrored the
    /// owner's zone, so revoking it leaves them nothing. That is a real thing an
    /// owner sometimes wants, and it is not a thing anybody should reach while
    /// trying to send an invitation, which is what it was one tap from before.
    ///
    /// Hidden for a member who joined: the sheet would offer them "Remove Me"
    /// dressed as group administration, and
    /// `cloudSharingControllerDidSaveShare` writes to the private store, which
    /// isn't where their copy of the group lives.
    ///
    /// Also hidden when the group is invitation-only, because `invitationAction`
    /// is then already presenting this same sheet as the primary button.
    @ViewBuilder
    private func manageAccess(share: CKShare) -> some View {
        if isOwner, share.publicPermission != .none {
            Button {
                showingManageAccess = true
            } label: {
                Label("Manage Access", systemImage: "person.2.badge.gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Adopts the share as CloudKit saved it.
    ///
    /// Only the permission can have changed here, never the URL, so the QR code
    /// is carried across rather than re-rasterised — but the captions below it
    /// are told from `publicPermission`, and they were reading a stale copy.
    private func refresh(_ share: CKShare) {
        guard case .ready(_, let container, let qrCode) = phase else { return }
        phase = .ready(share: share, container: container, qrCode: qrCode)
    }

    /// The owner stopped sharing, so there is no invitation left to show.
    ///
    /// Clearing the cached URL is the part that is easy to miss: `GroupListView`
    /// reads `cloudKitShareURL` to decide whether to mark a group as shared, and
    /// nothing else ever writes it back to `nil`. Left alone, a group the owner
    /// closed keeps its shared badge for good.
    ///
    /// Safe to act on without first confirming the share is really gone, which
    /// would be racy anyway: if this ever fires when sharing did *not* stop,
    /// reopening this screen calls `prepareShare`, which finds the share still
    /// there and caches its URL again. The cost of a false positive is a badge
    /// missing until the next visit.
    private func handleStopSharing() {
        group.cloudKitShareURL = nil
        try? context.save()
        showingManageAccess = false
        dismiss()
    }

    // MARK: - App Store code

    /// The other half of an invitation: somebody at the table who hasn't got
    /// Dutch yet.
    ///
    /// This is not a convenience. Tested on an iPhone with Dutch deleted,
    /// 2026-08-28: scanning the join code opens Safari on the bare
    /// `icloud.com/share/…` page, and that page offers **no route to the App
    /// Store**. It is a dead end — the guest has a URL, no app, and nothing to
    /// tap. Without the code below there is no path from "someone showed me a
    /// QR" to "I have Dutch installed" that doesn't involve searching the store
    /// by name, which is exactly what doesn't work for an app called Dutch.
    ///
    /// The `CKSharingSupported` note in CLAUDE.md describes a *different*
    /// situation — app installed but not registered as a handler, where iOS
    /// knew which app the container belonged to and could offer the store.
    /// Delete the app and that mapping goes with it. Don't infer one case from
    /// the other; this was assumed and it was wrong.
    ///
    /// Collapsed, smaller, and captioned on purpose. Two QR codes of the same
    /// size on one screen are indistinguishable at arm's length, and a host
    /// holding up the wrong one sends the whole table to the App Store while
    /// saying "scan this to join".
    @ViewBuilder
    private func appStoreDisclosure(share: CKShare) -> some View {
        VStack(spacing: 16) {
            Button {
                withAnimation(.snappy) { showingAppStoreCode.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(.appStoreCodeDisclosure)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(showingAppStoreCode ? 180 : 0))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if showingAppStoreCode {
                VStack(spacing: 12) {
                    if let appStoreCode {
                        Image(uiImage: appStoreCode)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .padding(12)
                            // White in both appearances for the same reason the
                            // join code is — see above.
                            .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .accessibilityLabel(Text(.appStoreCodeAccessibility))
                    } else {
                        // Matches the code's footprint exactly, so disclosing
                        // doesn't shove the caption down a second time when the
                        // image lands.
                        ProgressView()
                            .frame(width: 174, height: 174)
                    }

                    Text(.appStoreCodeCaption)
                        .font(.footnote.weight(.medium))

                    Group {
                        if share.publicPermission == .none {
                            Text(.appStoreCodeInvitationInstructions)
                        } else {
                            Text(.appStoreCodeInstructions)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
                .task {
                    guard appStoreCode == nil else { return }
                    appStoreCode = await QRCodeGenerator.image(for: Self.appStoreURL)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Preparing

    private func prepareShare() async {
        guard case .preparing = phase else { return }

        // The App Store screenshot harness cannot reach CloudKit: `share(for:)`
        // needs an iCloud account, so on a simulator this screen never leaves
        // `.preparing`. Before this hook the store's most important image — the
        // one that says "scan to join" — had to be shot on a physical device
        // and then have its *live* share URL painted out of the QR by hand,
        // because the code as captured was a working key to a real group.
        //
        // The share built here is never saved anywhere, and the URL its code
        // carries is the marketing site — see `screenshotShareURL` — so that
        // hazard cannot come back.
        // Gated on a launch argument as well as DEBUG: the shipping binary has
        // none of this, and a debug build still talks to CloudKit unless it was
        // launched by the harness.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-screenshots") {
            let placeholder = CKShare(recordZoneID: CKRecordZone(zoneName: "screenshots").zoneID)
            placeholder.publicPermission = .readWrite
            phase = .ready(
                share: placeholder,
                container: CKContainer(identifier: "iCloud.app.dutch.Dutch"),
                qrCode: await QRCodeGenerator.image(for: Self.screenshotShareURL)
            )
            return
        }
        #endif

        do {
            let (share, container) = try await resolveShare()

            // Cache the URL so the group list can show that it's shared
            // without re-hitting CloudKit.
            if let url = share.url, group.cloudKitShareURL != url {
                group.cloudKitShareURL = url
                try? context.save()
            }

            phase = .ready(
                share: share,
                container: container,
                qrCode: await QRCodeGenerator.image(for: share.url)
            )
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// The share to display, created only if this group is ours.
    ///
    /// `CloudSharingService.share(for:)` falls back to `container.share(_:to:)`
    /// when a group has no share yet, and that call is meaningless for a group
    /// that arrived from somebody else's invitation — it would ask Core Data to
    /// create a zone for a record living in the shared store. A joined group
    /// always has a share already, since that is how it got here, so looking one
    /// up is the whole job; if it is somehow missing, saying so beats inventing
    /// a second share for a group we don't own.
    private func resolveShare() async throws -> (CKShare, CKContainer) {
        guard GroupLimit.isJoined(group) else {
            return try await CloudSharingService.share(for: group)
        }
        guard let share = try CloudSharingService.existingShare(for: group) else {
            throw CloudSharingService.SharingError.noShareAvailable
        }
        return (share, CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier))
    }
}

#Preview {
    ShareGroupView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
