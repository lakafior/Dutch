/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import CoreData
import CoreTransferable
import DutchKit

/// Detail screen for a single group: members, expenses, and settlement summary.
///
/// Section order is deliberate — standing, then the payments that fix it, then
/// the log. The settlement is the answer the user came for; the expense list is
/// reference material, and used to sit above it.
struct GroupDetailView: View {
    /// Observed for the group's own fields — its name and currency.
    @ObservedObject var group: ExpenseGroup

    /// The contents come from fetch requests rather than from `group.members`
    /// and `group.expenses`, so that *editing* an expense recomputes the
    /// balances. Observing the group alone only catches changes to the group
    /// itself, and correcting an amount never touches it. See
    /// `Expense.request(in:)`.
    @FetchRequest private var members: FetchedResults<Person>
    @FetchRequest private var expenses: FetchedResults<Expense>

    init(group: ExpenseGroup) {
        self.group = group
        _members = FetchRequest(fetchRequest: Person.request(in: group), animation: .snappy)
        _expenses = FetchRequest(fetchRequest: Expense.request(in: group), animation: .snappy)
    }

    @Environment(\.managedObjectContext) private var context

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var showingShareSheet = false
    @State private var showingEditGroup = false
    @State private var membersPendingDeletion: [Person] = []
    @State private var formTarget: FormTarget?
    @State private var editTarget: EditTarget?
    /// The transfer whose amount was tapped, if any. Holds the `Transfer`
    /// rather than the two `Person` records because the row has only the
    /// former, and `record` already does that lookup for the full payment.
    @State private var partialTarget: Transfer?
    @State private var errorMessage: String?
    /// Bumped on each successful add so the haptic fires once per confirmed
    /// write, rather than on any change to the counts (deletes included).
    @State private var addCount = 0
    /// Which member is the person holding this phone, or `nil` if they haven't
    /// said. Mirrored into `@State` rather than read from `ExpenseDefaults` in
    /// the body, because `UserDefaults` is not observable and the badge would
    /// otherwise not move until something else redrew the screen.
    @State private var me: Person?

    /// People on the share who aren't linked to a member yet.
    ///
    /// `@State` rather than computed in the body: it reads the cached `CKShare`,
    /// which is not a fetched object and so cannot drive a redraw on its own,
    /// and the body runs far too often to pay for that lookup each time.
    @State private var unclaimedJoiners: [String] = []

    private var store: GroupStore { GroupStore(context: context) }

    /// Consulted for a pending `.newExpense`, which `GroupListView` pushes this
    /// screen for but cannot act on — the form is a sheet belonging here.
    private var router: AppRouter { AppRouter.shared }

    var body: some View {
        // Gathered once and passed down. Read as computed properties these were
        // re-evaluated at every mention: one full settlement per member row,
        // two more for the Settle Up section, and the member and expense sets
        // sorted four times each.
        let contents = GroupContents(
            group: group,
            members: Array(members),
            expenses: Array(expenses)
        )

        List {
            GroupSummarySection(group: group, contents: contents)

            GroupMembersSection(
                contents: contents,
                currencyCode: group.currency,
                me: me,
                unclaimedJoiners: unclaimedJoiners,
                onEdit: { member, avatar in
                    editTarget = EditTarget(member: member, avatar: avatar)
                },
                onSetIdentity: setIdentity,
                onDelete: { membersPendingDeletion = $0 },
                onAdd: { showingAddMember = true }
            )

            SettleUpSection(
                contents: contents,
                currencyCode: group.currency,
                me: me,
                onSettle: { record($0, in: contents) },
                onPartial: { partialTarget = $0 }
            )

            ExpenseLogSection(
                contents: contents,
                currencyCode: group.currency,
                onAddFirst: { showingAddExpense = true },
                onUndo: undo,
                onOpen: { expense, mode in
                    formTarget = FormTarget(expense: expense, mode: mode)
                },
                onDelete: delete(at:from:)
            )
        }
        // Here as well as on the group list, because this is the screen someone
        // stares at waiting for an expense their friend just added. No status
        // line to go with it: the list is where "is everything here?" is asked,
        // and this screen is already dense. See `CloudSyncMonitor` for what the
        // pull actually does.
        // Re-read after the sync, not before: somebody accepting the invitation
        // arrives as an import, and the pull is the gesture people use when they
        // are waiting for exactly that.
        .refreshable {
            await CloudSyncMonitor.shared.refresh()
            unclaimedJoiners = CloudIdentity.unclaimedJoiners(in: group)
        }
        .navigationTitle(group.name ?? String(localized: .unnamedGroup))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Leftmost of the three: renaming and restyling is something
                // you do once, and it has no business sitting where the thumb
                // lands for "add an expense".
                //
                // In the toolbar rather than on the summary block, because that
                // block only exists once there is spending — and a brand new
                // group with a name typed in a hurry is exactly the one you
                // want to fix.
                Button {
                    showingEditGroup = true
                } label: {
                    Label("Edit Group", systemImage: "pencil")
                }

                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share Group", systemImage: "square.and.arrow.up")
                }
            }

            // Adding an expense is the one thing on this screen anybody does
            // more than once a trip, and in the top-right corner it was the
            // furthest point on a 6.9" phone from the thumb holding it. The
            // other two are once-per-trip and stay where they were: moving the
            // whole toolbar down would just relocate the problem and cost the
            // grouping that says which of the three is the point.
            //
            // Spaced to the centre rather than left in the leading slot, where
            // a lone bottom-bar item sits under the same thumb that just
            // reached past it.
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()

                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add Expense", systemImage: "plus.circle.fill")
                }
                // Titled as well as drawn. A bare glyph in a bar with nothing
                // else in it has no neighbours to be understood against, and
                // this is the action the screen exists to offer.
                .labelStyle(.titleAndIcon)
                // Filled, not plain. As tinted text on a toolbar this was the
                // primary action of the whole screen drawn exactly like a
                // link — reported as "barely visible", which it was: nothing
                // around it to be read against, and a glass bar behind it.
                // `.borderedProminent` is the system's own way of saying "this
                // is the one", and `.large` buys the height that makes it read
                // as a button from across the table.
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .font(.body.weight(.semibold))
                // The group's own colour rather than the app accent. It is the
                // same colour as the icon in the summary block directly above
                // and the row this screen was opened from, so the primary
                // action belongs to *this* group rather than looking like a
                // system control that wandered in.
                //
                // Safe from being read as a balance: `PaletteColor` excludes
                // red and green precisely so a group's tint can never be
                // confused with owing or being owed.
                .tint(group.appearance.color.tint)
                .disabled(contents.members.isEmpty)

                Spacer()
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            ExpenseFormView(group: group)
        }
        .sheet(item: $formTarget) { target in
            switch target.mode {
            case .edit:
                ExpenseFormView(editing: target.expense, in: group)
            case .duplicate:
                ExpenseFormView(duplicating: target.expense, in: group)
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(onAdd: addMember)
        }
        .sheet(item: $editTarget) { target in
            EditMemberSheet(member: target.member, avatar: target.avatar) { name, color, symbol in
                updateMember(target.member, name: name, color: color, symbol: symbol)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareGroupView(group: group)
        }
        .sheet(isPresented: $showingEditGroup) {
            EditGroupSheet(group: group, onSave: updateGroup) { archived in
                setArchived(archived)
            }
        }
        .sheet(item: $partialTarget) { transfer in
            PartialPaymentSheet(
                transfer: transfer,
                currencyCode: group.currency,
                isMe: transfer.from.id == me?.id
            ) { amount, date in
                record(transfer, amount: amount, on: date, in: contents)
            }
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: confirmMemberDeletion)
            Button("Cancel", role: .cancel) { membersPendingDeletion = [] }
        } message: {
            Text(deletionMessage)
        }
        .environment(\.expenseGroupTint, group.appearance.color.tint)
        .sensoryFeedback(.success, trigger: addCount)
        .errorBanner($errorMessage)
        // Resolved against the current roster on every appearance, so an
        // identity whose member was deleted — here or on another device —
        // quietly falls back to third person instead of pointing at nothing.
        .onAppear {
            // Compared before assigning, because `@State` invalidates on any
            // write and not only on a change of value — and this runs on every
            // return from the expense form, where the answer is the same one it
            // was when the sheet went up.
            let resolved = ExpenseDefaults.me(in: group, among: contents.members)
            if resolved != me { me = resolved }
            // What makes "add an expense" mean something without a group being
            // named — from the Action button, the Home Screen icon, or Siri.
            // Recorded on arrival rather than on any edit, because the question
            // it answers is "which trip am I on", and opening a group is the
            // whole of the evidence for that.
            ExpenseDefaults.rememberOpened(group)
            unclaimedJoiners = CloudIdentity.unclaimedJoiners(in: group)
            openPendingExpense()
        }
        .onChange(of: router.destination) { openPendingExpense() }
    }

    /// Opens the form if an intent asked for a new expense *in this group*.
    ///
    /// Checked against the group rather than taken on trust: the destination is
    /// global, and this screen can be on top of a different group entirely when
    /// one arrives. Consumed either way once acted on, so returning here later
    /// doesn't reopen the sheet.
    private func openPendingExpense() {
        guard case .newExpense(let id) = router.destination, id == group.id else { return }
        router.destination = nil
        // Nothing to enter until somebody can be charged for it, and the form
        // would open with an empty roster and a disabled Save.
        guard !members.isEmpty else {
            errorMessage = String(localized: "Add a member to this group first.")
            return
        }
        showingAddExpense = true
    }

    // MARK: - Member deletion

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { !membersPendingDeletion.isEmpty },
            set: { if !$0 { membersPendingDeletion = [] } }
        )
    }

    private var deletionTitle: String {
        guard membersPendingDeletion.count == 1 else {
            return String(localized: "Remove \(membersPendingDeletion.count) members?")
        }
        let name = membersPendingDeletion.first?.name ?? String(localized: "this member")
        return String(localized: "Remove \(name)?")
    }

    /// Names the cascade explicitly. Deleting the expenses they paid for is the
    /// correct behaviour — see `GroupStore.delete(_ member:)` — but it is not
    /// something a swipe should do silently.
    ///
    /// Both halves of the cascade matter. Counting only `paidExpenses` claimed
    /// "this won't change anyone else's balance" for a member who had paid for
    /// nothing but was still splitting other people's expenses — removing them
    /// drops them from `splitAmong`, so those expenses re-divide between fewer
    /// people and every remaining balance moves. The warning said one thing and
    /// the screen behind it did another.
    private var deletionMessage: String {
        let (removed, resplit) = deletionImpact

        switch (removed, resplit) {
        case (0, 0):
            return String(localized: "This won't change anyone else's balance.")
        case (0, _):
            return String(localized: "\(ItemCount.expenses(resplit)) they were splitting gets divided between everyone left, so balances change.")
        case (_, 0):
            return String(localized: "This also removes \(ItemCount.expenses(removed)) they paid for, and recalculates everyone's balance.")
        default:
            return String(localized: "This also removes \(ItemCount.expenses(removed)) they paid for and re-splits \(ItemCount.expenses(resplit)) between everyone left. Balances change.")
        }
    }

    /// Expenses that disappear with the member, and surviving expenses that get
    /// re-divided without them.
    ///
    /// Both are counted over sets: removing two members at once would otherwise
    /// double-count an expense they were splitting together.
    private var deletionImpact: (removed: Int, resplit: Int) {
        var removed: Set<Expense> = []
        var shared: Set<Expense> = []

        for member in membersPendingDeletion {
            removed.formUnion((member.paidExpenses as? Set<Expense>) ?? [])
            shared.formUnion((member.sharedExpenses as? Set<Expense>) ?? [])
        }

        return (removed.count, shared.subtracting(removed).count)
    }

    private func confirmMemberDeletion() {
        let doomed = membersPendingDeletion
        membersPendingDeletion = []
        do {
            for member in doomed {
                try store.delete(member)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func addMember(named name: String) {
        do {
            try store.addMember(named: name, to: group)
            addCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateGroup(name: String, appearance: GroupAppearance) {
        do {
            try store.update(group, name: name, appearance: appearance)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Archiving from here leaves the screen open on purpose. The group has not
    /// gone anywhere — it is still being looked at, and popping back to the list
    /// would read as a delete.
    private func setArchived(_ archived: Bool) {
        do {
            try store.setArchived(archived, for: group)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Takes back a recorded settlement, restoring the debt it cleared.
    ///
    /// Deleting the payment is the whole of it: the settlement maths has no
    /// concept of one — `GroupStore.recordPayment` writes an ordinary expense —
    /// so removing that record puts every balance back exactly where it stood
    /// before the tap.
    private func undo(_ payment: Expense) {
        do {
            try store.delete(payment)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet, from expenses: [Expense]) {
        do {
            for index in offsets {
                try store.delete(expenses[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Logs one of the suggested payments as having happened.
    ///
    /// The transfer is expressed in `Participant`s, which the store cannot
    /// write — it needs the `Person` records behind them, hence the lookup.
    /// A transfer naming somebody who is no longer in the group can't be
    /// recorded, and silently doing nothing would look like the tap missed.
    ///
    /// `amount` and `date` default to the whole transfer and to now, which is
    /// what the button passes — it has no form to ask with and must stay one
    /// tap. `PartialPaymentSheet` passes both. Nothing below this line
    /// tells the two apart: a payment is an ordinary expense flagged
    /// `isReimbursement`, and the settlement recomputes from balances, so
    /// five instalments clear a debt exactly as one payment does — and the
    /// swipe-to-undo on each row backs them out one at a time.
    private func record(
        _ transfer: Transfer,
        amount: Money? = nil,
        on date: Date = Date(),
        in contents: GroupContents
    ) {
        guard
            let payer = contents.person[transfer.from.id],
            let recipient = contents.person[transfer.to.id]
        else {
            errorMessage = String(localized: "That member is no longer in this group.")
            return
        }

        do {
            try store.recordPayment(
                from: payer,
                to: recipient,
                amount: amount ?? transfer.amount,
                in: group,
                on: date
            )
            addCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Records who this device belongs to, both ways at once.
    ///
    /// The local key first, because it is the one that cannot fail: it needs no
    /// iCloud account and no network, and it is all a group that was never
    /// shared will ever have. The claim then rides on top when there *is* an
    /// account, which is what carries the answer to this person's other devices
    /// and to everyone else's copy of the group.
    ///
    /// A failed claim is deliberately quiet. Identity is a label — the balances
    /// do not depend on it — and an error banner over "you tapped your own name"
    /// would be a louder failure than the thing that failed.
    /// Applies a rename and a colour from the sheet. Loud on failure, unlike
    /// `setIdentity`: this one is a write to a record everybody in the group
    /// sees, so a save that didn't happen is worth saying so.
    private func updateMember(
        _ member: Person,
        name: String,
        color: PaletteColor?,
        symbol: Emblem?
    ) {
        do {
            try store.update(member, name: name, color: color, symbol: symbol)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setIdentity(_ member: Person?) {
        ExpenseDefaults.rememberMe(member, in: group)
        try? store.claim(member, in: group)
        withAnimation(.snappy) { me = member }
    }

}

#Preview {
    NavigationStack {
        GroupDetailView(group: PersistenceController.previewGroup)
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}
