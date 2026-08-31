/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit
import SwiftUI

/// Main screen showing all expense groups — both the user's own and any that
/// have been shared with them.
struct GroupListView: View {
    @Environment(\.managedObjectContext) private var context

    /// Reads go through `@FetchRequest` so changes synced down from CloudKit
    /// refresh the list on their own, with no manual reload.
    ///
    /// The spring is deliberate: `.default` is an ease, which reads as
    /// mechanical when a row arrives from a sync the user didn't initiate.
    @FetchRequest(
        fetchRequest: GroupListView.groupsRequest,
        animation: .spring(response: 0.35, dampingFraction: 0.8)
    )
    private var groups: FetchedResults<ExpenseGroup>

    /// Only the groups. Each row fetches its own contents — and prefetches the
    /// relationships the settlement walks — because a row that read them off
    /// the relationship sets could not see an expense being edited. See
    /// `Expense.request(in:)`.
    private static var groupsRequest: NSFetchRequest<ExpenseGroup> {
        let request = ExpenseGroup.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ExpenseGroup.creationDate, ascending: false)
        ]
        return request
    }

    /// Whether this device has bought its way past the free group limit.
    ///
    /// A singleton rather than a `@StateObject`, because the entitlement is a
    /// fact about the Apple Account and not about this view — the paywall
    /// observes the same instance, which is what lets buying from there unblock
    /// the create that opened it.
    @ObservedObject private var purchases = PurchaseStore.shared

    /// Drives the pull-to-refresh gesture and the status line under the list.
    /// A singleton for the same reason `purchases` is: it describes the account
    /// and the container, not this screen, and the detail screen pulls on the
    /// same one.
    @ObservedObject private var sync = CloudSyncMonitor.shared

    /// Path-based navigation so creating a group can push straight into it.
    @State private var path: [ExpenseGroup] = []
    @State private var showingNewGroup = false
    @State private var showingJoinGroup = false
    @State private var showingSettings = false
    @State private var errorMessage: String?

    /// Set with `reachedLimit` when a create was blocked, and without it when
    /// the user opened the paywall themselves.
    @State private var paywallReason: PaywallReason?

    /// Whether the archive is open. Collapsed on every launch on purpose: the
    /// whole feature is that a finished trip stops taking up the list, and a
    /// disclosure that remembered being open would undo that for the one user
    /// who ever opened it.
    @State private var showingArchive = false

    private enum PaywallReason: Identifiable {
        case blocked
        case browsing
        var id: Self { self }
    }

    /// Set when the paywall interrupted a create, so that buying resumes it.
    /// Survives the sheet's own state because `sheet(item:)` has cleared the
    /// reason by the time `onDismiss` runs.
    @State private var resumeCreateAfterPaywall = false

    /// Set when a create was refused from inside `NewGroupSheet`, so the
    /// paywall waits for that sheet to actually be gone.
    @State private var blockedAfterSheet = false

    /// Held until the sheet has finished dismissing — pushing onto the path
    /// while a sheet is still on screen is a reliable way to have the push
    /// silently swallowed.
    @State private var groupToOpen: ExpenseGroup?

    /// Where an App Intent or the Home Screen quick action wants the app to be.
    /// This screen owns the navigation path, so it is the only thing that can
    /// act on one.
    private var router: AppRouter { AppRouter.shared }

    private var store: GroupStore { GroupStore(context: context) }

    /// The list is fetched unfiltered and split here rather than filtered in
    /// the fetch, because `GroupLimit` counts `groups` and archiving must not
    /// change that count — see the note on `GroupLimit.createdCount`.
    private var active: [ExpenseGroup] { groups.filter { !$0.isArchived } }
    private var archived: [ExpenseGroup] { groups.filter(\.isArchived) }

    /// The finished trips, folded away.
    ///
    /// A disclosure rather than a second screen: the navigation path is typed
    /// `[ExpenseGroup]`, so a separate archive destination would mean widening
    /// it to an enum and rewriting every push for a list most people will open
    /// once. Collapsed, this is a single row — which is the entire point, since
    /// the complaint was that the list never shrinks.
    ///
    /// Absent entirely until something is in it. A permanently visible
    /// *Archived (0)* is a row that explains a feature nobody has used yet.
    @ViewBuilder
    private var archiveSection: some View {
        if !archived.isEmpty {
            Section {
                DisclosureGroup(isExpanded: $showingArchive) {
                    ForEach(archived) { group in
                        NavigationLink(value: group) {
                            GroupRow(group: group)
                        }
                        .swipeActions(edge: .leading) {
                            archiveButton(for: group)
                        }
                    }
                    .onDelete { delete(at: $0, from: archived) }
                } label: {
                    Label {
                        Text(archivedCount(archived.count))
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One button for both directions, so the two can't drift apart in wording
    /// or in which edge they live on.
    ///
    /// The leading edge, opposite Delete. Archiving is the *un*-destructive
    /// half of "I am finished with this trip", and putting it under the same
    /// thumb sweep as the action that destroys every expense in it is how a
    /// swipe becomes something people stop doing.
    private func archiveButton(for group: ExpenseGroup) -> some View {
        Button {
            setArchived(!group.isArchived, for: group)
        } label: {
            if group.isArchived {
                Label("Unarchive", systemImage: "tray.and.arrow.up")
            } else {
                Label("Archive", systemImage: "archivebox")
            }
        }
        .tint(group.isArchived ? .blue : .indigo)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(active) { group in
                        NavigationLink(value: group) {
                            GroupRow(group: group)
                        }
                        .swipeActions(edge: .leading) {
                            archiveButton(for: group)
                        }
                    }
                    .onDelete { delete(at: $0, from: active) }
                }

                archiveSection

                // The always-available way in. Without it the only route to
                // "Restore Purchases" would be to first get blocked by the
                // limit, which is a bad experience for someone whose purchase
                // simply hasn't synced yet — and something App Review checks
                // for. Disappears once the purchase is in.
                if !purchases.hasUnlimitedGroups && !groups.isEmpty {
                    Section {
                        Button {
                            paywallReason = .browsing
                        } label: {
                            Label("Dutch Unlimited", systemImage: "infinity")
                        }
                    } footer: {
                        Text(.pricingDescription)
                    }
                }
            }
            // The gesture this app is expected to have, given that everything
            // in it arrives from somebody else's phone. It cannot make CloudKit
            // fetch — no API can — so read `CloudSyncMonitor` before assuming
            // more of it than it does.
            .refreshable { await sync.refresh() }
            .navigationDestination(for: ExpenseGroup.self) { group in
                GroupDetailView(group: group)
            }
            // Outside the List, so the empty state centres on the screen
            // instead of inside a single inset row with a separator under it.
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "rectangle.3.group")
                    } description: {
                        Text(.createOrJoinAGroup)
                    } actions: {
                        // An empty state without a next action is a dead end.
                        Button("Create a Group", action: requestNewGroup)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Dutch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingJoinGroup = true
                    } label: {
                        Label("Join a Group", systemImage: "qrcode.viewfinder")
                    }
                }
                // Leading, so it sits toward the title rather than crowding the
                // primary action — and second in the group, so the action a
                // person came to tap is still the one at the edge. It cannot go
                // beside the large title itself: a `.principal` item replaces
                // the title and forces inline mode.
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusIndicator()
                }
                // Trailing rather than leading, and before the primary action
                // so the button somebody came to tap keeps the edge. Settings
                // is a place people go looking for deliberately; it does not
                // need to be the easiest thing to hit.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: requestNewGroup) {
                        Label("New Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewGroup, onDismiss: openPendingGroup) {
                NewGroupSheet(onCreate: createGroup)
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $paywallReason, onDismiss: resumeBlockedCreate) { reason in
                PaywallView(reachedLimit: reason == .blocked)
            }
            // Loads the price and re-checks the entitlement. Here rather than
            // in the paywall alone so a device that was offline at launch has
            // both by the time anyone taps anything.
            .task { await purchases.load() }
            .errorBanner($errorMessage)
            // Both, because an intent can arrive either way: on a cold launch
            // the destination is already set by the time this appears, and on a
            // warm one it changes while the list is on screen.
            .onAppear(perform: followRouter)
            .onChange(of: router.destination) { followRouter() }
        }
    }

    // MARK: - Actions

    /// Whether another group can be created, by the rule in `GroupLimit`.
    private var canCreateGroup: Bool {
        GroupLimit.canCreate(among: groups, unlocked: purchases.hasUnlimitedGroups)
    }

    /// The only way the new-group sheet opens.
    ///
    /// Both entry points go through here so the gate cannot be reached around,
    /// and so the paywall replaces the sheet rather than appearing on top of it
    /// — being asked for a name and *then* for money is a worse version of the
    /// same refusal.
    private func requestNewGroup() {
        if canCreateGroup {
            showingNewGroup = true
        } else {
            resumeCreateAfterPaywall = true
            paywallReason = .blocked
        }
    }

    /// Picks the interrupted create back up once the paywall closes.
    ///
    /// Only after a purchase, and only if the paywall was blocking something —
    /// somebody who tapped "Not Now" asked for the list, not for the sheet they
    /// were just refused. Nothing happens on the browsing path either.
    private func resumeBlockedCreate() {
        defer { resumeCreateAfterPaywall = false }
        guard resumeCreateAfterPaywall, canCreateGroup else { return }
        showingNewGroup = true
    }

    private func createGroup(
        named name: String,
        currencyCode: String,
        appearance: GroupAppearance
    ) {
        // Checked again on the way in, not just on the way to the sheet. The
        // entitlement can change while the sheet is open — a refund, or a
        // Family Sharing grant withdrawn — and this is the last point before a
        // group actually exists.
        //
        // The paywall is deferred rather than presented here for the same
        // reason `groupToOpen` is: this runs while `NewGroupSheet` is still on
        // screen dismissing itself, and a sheet presented into that gets
        // silently swallowed — which would read as a Create button that does
        // nothing at all.
        guard canCreateGroup else {
            blockedAfterSheet = true
            return
        }

        do {
            groupToOpen = try store.createGroup(
                named: name,
                currencyCode: currencyCode,
                appearance: appearance
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pushes the group an intent or a Home Screen action asked for.
    ///
    /// The path is set rather than appended to, so arriving from outside always
    /// lands on that group whatever was on screen before — and so a second
    /// invocation doesn't stack the same group twice.
    ///
    /// `.newExpense` is left in place rather than cleared: `GroupDetailView`
    /// consumes it once it is on screen and can open its own sheet. Clearing it
    /// here would push the group and then swallow the reason for the push.
    private func followRouter() {
        guard let destination = router.destination else { return }
        guard let group = GroupLookup.group(id: destination.groupID, in: context) else {
            // The group was deleted, or the invitation was never accepted on
            // this device. Saying so beats a tap that appears to do nothing.
            router.destination = nil
            errorMessage = "That group isn't on this device."
            return
        }

        path = [group]
        if case .group = destination {
            router.destination = nil
        }
    }

    /// A new group is empty and useless until it has members, so drop the user
    /// into it rather than leaving them on a list to tap the row they just made.
    private func openPendingGroup() {
        if blockedAfterSheet {
            blockedAfterSheet = false
            resumeCreateAfterPaywall = true
            paywallReason = .blocked
            return
        }

        guard let group = groupToOpen else { return }
        groupToOpen = nil
        path = [group]
    }

    /// Offsets index the *section's* array, not the fetch. Two sections draw
    /// from one `FetchedResults` now, so deleting the second archived row by
    /// index into `groups` would delete whichever group happened to sit second
    /// in the whole list.
    private func delete(at offsets: IndexSet, from list: [ExpenseGroup]) {
        do {
            for index in offsets {
                try store.delete(list[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Counted in the catalog, not in Swift. Polish needs four plural
    /// categories where English needs two, so any `== 1 ? singular : plural`
    /// here would be a bug for it.
    private func archivedCount(_ value: Int) -> String {
        String(localized: "\(value) archived")
    }

    private func setArchived(_ archived: Bool, for group: ExpenseGroup) {
        do {
            try store.setArchived(archived, for: group)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct GroupRow: View {
    /// Observed for the group's own fields — name and share URL.
    @ObservedObject var group: ExpenseGroup

    /// The row's numbers come from fetch requests for the same reason the
    /// detail screen's do: an expense edited anywhere changes the `Expense`
    /// and nothing on the group, so a row reading the relationship set keeps
    /// showing the total it had when it was last built. See
    /// `Expense.request(in:)`.
    @FetchRequest private var members: FetchedResults<Person>
    @FetchRequest private var expenses: FetchedResults<Expense>

    /// Which member is the person holding this phone, or `nil` if they haven't
    /// said — in which case the row falls back to reporting the group as a
    /// whole, which is all it could say before identity existed.
    @State private var me: Person?

    init(group: ExpenseGroup) {
        self.group = group
        _members = FetchRequest(fetchRequest: Person.request(in: group))
        _expenses = FetchRequest(fetchRequest: Expense.request(in: group))
    }

    var body: some View {
        // One settlement per row. `totalSpent` and `transfers` were separate
        // walks of the same expenses, and `transfers` rebuilt the balances on
        // top of that — three passes to render two numbers.
        let settlement = group.settlement(members: Array(members), expenses: Array(expenses))
        let memberCount = members.count
        let expenseCount = expenses.count
        let standing = me?.id.map { Standing(balance: settlement.balanceByParticipant[$0]) }

        // The tile sits outside the fitting, so it is present in both branches
        // and the fit is decided on the width the text actually gets.
        HStack(spacing: 12) {
            GroupIcon(group.appearance)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    identity(memberCount: memberCount, expenseCount: expenseCount)
                    Spacer(minLength: 12)
                    money(settlement, standing: standing, alignment: .trailing)
                }

                // Once names, currency and type size stop sharing a line, stack
                // rather than truncate.
                VStack(alignment: .leading, spacing: 8) {
                    identity(memberCount: memberCount, expenseCount: expenseCount)
                    money(settlement, standing: standing, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            standing?.accessibleValue(isMe: true, currencyCode: group.currency)
                ?? groupAccessibleValue(settlement)
        )
        .onAppear { resolveIdentity() }
        // Identity is set on the detail screen, which sits directly on top of
        // this list. `UserDefaults` is not observable and popping back doesn't
        // re-run `onAppear` on a row that never left the screen, so without
        // this the row would keep showing the group total until something else
        // redrew it.
        //
        // Specifically `identityDidChange` and not `UserDefaults`'s own
        // notification: that one also carries `CloudSyncMonitor`'s `lastSync`
        // stamp, written to this same suite on every import, which had every
        // row on screen re-resolving identity once per sync to reach the answer
        // it already had.
        .onReceive(NotificationCenter.default.publisher(for: ExpenseDefaults.identityDidChange)) { _ in
            resolveIdentity()
        }
        .onChange(of: members.count) { resolveIdentity() }
    }

    /// Re-resolves against the current roster on every appearance, so an
    /// identity whose member was deleted — here or on another device — quietly
    /// falls back to the group-wide numbers instead of pointing at nothing.
    private func resolveIdentity() {
        let resolved = ExpenseDefaults.me(in: group, among: Array(members))
        guard resolved != me else { return }
        withAnimation(.snappy) { me = resolved }
    }

    @ViewBuilder
    private func identity(memberCount: Int, expenseCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(group.name ?? "Unnamed")
                    .font(.headline)

                if group.cloudKitShareURL != nil {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Shared group")
                }
            }

            // No word sequence here, deliberately: it is a label for pairing a
            // new phone with a group and belongs next to the QR code on the
            // share screen, not on the list somebody reads every day.

            // Both glyphs filled, both labelled: the old row mixed
            // `person.2.fill` with an outline `person` in the same group, and
            // read to VoiceOver as two bare numbers.
            HStack(spacing: 12) {
                Label("\(memberCount)", systemImage: "person.2.fill")
                    .accessibilityLabel("\(memberCount) members")
                Label("\(expenseCount)", systemImage: "list.bullet.rectangle.fill")
                    .accessibilityLabel("\(expenseCount) expenses")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
    }

    /// The one number worth reading from the list.
    ///
    /// Once the device knows which member is holding it, that number is what
    /// *they* owe or are owed — the question anyone opening a bill-splitting
    /// app came to ask, and previously one tap away on every group. The group's
    /// total spent gives up its place here rather than sharing the column with
    /// it: two figures in the same corner make each of them a thing to decode,
    /// and the total is the hero of the detail screen, which is a tap away.
    ///
    /// Without an identity there is no personal figure to show, so the row says
    /// exactly what it always did.
    @ViewBuilder
    private func money(
        _ settlement: ExpenseGroup.Settlement,
        standing: Standing?,
        alignment: HorizontalAlignment
    ) -> some View {
        let pending = settlement.transfers.count

        VStack(alignment: alignment, spacing: 2) {
            switch standing {
            case .owes(let amount), .isOwed(let amount):
                Text(amount.formatted(in: group))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(standing?.tint ?? .primary)
                    // The figure changes whenever anyone adds an expense,
                    // including from another device — roll the digits so it's
                    // visible.
                    .motionContentTransition(.numericText())

                Text(standing?.caption(isMe: true) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .settled:
                Text(.settledUp)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                // Being square with everyone doesn't mean the group is done,
                // and a row that stopped at "Settled up" hid that.
                Text(pending == 0 ? "everyone's even" : "\(pending) to settle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case nil:
                Text(settlement.totalSpent.formatted(in: group))
                    .font(.headline)
                    .monospacedDigit()
                    .motionContentTransition(.numericText())

                Text(pending == 0 ? "Settled up" : "\(pending) to settle")
                    .font(.caption2)
                    .foregroundStyle(pending == 0 ? .secondary : .primary)
            }
        }
        .animation(.snappy, value: standing)
        .animation(.snappy, value: settlement.totalSpent)
    }

    /// What the row says to VoiceOver when it has no personal figure to report.
    private func groupAccessibleValue(_ settlement: ExpenseGroup.Settlement) -> String {
        let total = settlement.totalSpent.formatted(in: group)
        let pending = settlement.transfers.count
        return pending == 0
            ? String(localized: "\(total) total, settled up")
            : String(localized: "\(total) total, \(pending) payments to settle")
    }
}

#Preview {
    GroupListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
