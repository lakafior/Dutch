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
        let contents = Contents(
            group: group,
            members: Array(members),
            expenses: Array(expenses)
        )

        List {
            summarySection(contents)
            membersSection(contents)
            settleUpSection(contents)
            expensesSection(contents)
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
            errorMessage = "Add a member to this group first."
            return
        }
        showingAddExpense = true
    }

    // MARK: - Sections

    /// The group's identity, and its total once there is one.
    ///
    /// The section itself is unconditional — it is the only thing on this screen
    /// that says *which* group you are looking at, and a group that hasn't been
    /// spent in yet is precisely the one you might have opened by mistake. What
    /// is conditional is the number: a large `0.00` on a brand new group is
    /// noise sitting where the useful figure will eventually be, so until then
    /// the block is the tile and a quiet line about where the group stands.
    private func summarySection(_ contents: Contents) -> some View {
        Section {
            // The same tile as the list row, so arriving here confirms you
            // opened the group you meant to. Larger, because this is the one
            // place it isn't competing with a column of others.
            HStack(alignment: .top, spacing: 16) {
                GroupIcon(group.appearance, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if contents.spendingCount > 0 {
                        Text(.totalSpent)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(contents.totalSpent.formatted(in: group))
                            .font(.largeTitle.weight(.semibold))
                            .monospacedDigit()
                            .motionContentTransition(.numericText())

                        // Counts the spending, not the rows: settling up adds an
                        // entry to the list below but buys nothing, and "12
                        // expenses" over a total that added up nine of them is
                        // just wrong.
                        Text("\(expenseCount(contents.spendingCount)) · \(memberCount(contents.members.count))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(.nothingSpentYet)
                            .font(.headline)

                        // Only once there is a roster. "0 members" next to
                        // "nothing spent yet" is the same fact told twice, and
                        // the members section below already asks for the first
                        // one in words.
                        if !contents.members.isEmpty {
                            Text(memberCount(contents.members.count))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: contents.totalSpent)
            .accessibilityElement(children: .combine)

            breakdown(contents)

            // Withheld until there is something to summarise: the shared text
            // is the total and the payments settling it, and neither exists yet.
            //
            // Here rather than in the toolbar, for two reasons. The toolbar
            // already owns a share glyph — that one invites people into the
            // group, and hanging a second, different share off the same
            // symbol makes both a coin flip. And this section is exactly
            // the thing being shared: the total, and what it resolves to.
            if contents.spendingCount > 0 {
                ShareLink(
                    item: SharedSummary(summary: contents.summary),
                    preview: SharePreview(group.name ?? String(localized: .unnamedGroup))
                ) {
                    Label("Share Summary", systemImage: "doc.plaintext")
                }
                .accessibilityHint("Copies who owes whom, the total and the expense list as text")
            }
        }
    }

    /// Where the money went.
    ///
    /// The answer to what a category is *for*. Before this, an expense could be
    /// filed and the app never used the filing — a labelled field that did no
    /// work, which is exactly how it was reported.
    ///
    /// Only once something has been categorised. A group nobody files gets a
    /// single **Uncategorised** bar equal to the total it already read two lines
    /// above, which is a chart of one fact repeated.
    ///
    /// In the summary section rather than on a screen of its own: it belongs
    /// under the total it decomposes, it costs no navigation, and a breakdown
    /// behind a push is one most people would never open — the same argument
    /// that keeps **Share Summary** here instead of in the toolbar.
    @ViewBuilder
    private func breakdown(_ contents: Contents) -> some View {
        let rows = contents.spendByCategory
        if rows.contains(where: { $0.key != nil }) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.key) { row in
                    BreakdownRow(
                        category: row.key,
                        total: row.total,
                        fraction: row.fraction,
                        currencyCode: group.currency
                    )
                }
            }
            .padding(.vertical, 4)
            .animation(.snappy, value: contents.totalSpent)
        }
    }

    private func membersSection(_ contents: Contents) -> some View {
        Section {
            // No placeholder row while this is empty. The header says what the
            // section is and the button below says what to do about it, so a
            // third line saying the same thing was the redundancy people
            // reported. `expensesSection` already works this way — a
            // placeholder *or* an action, never both — and this was the one
            // section that stacked the two.
            //
            // The header is what stays. Making it read "Add Members" while
            // empty is the other obvious fix and is worse: a section header is
            // what VoiceOver announces before every row beneath it, so a verb
            // there is read out immediately before the button that repeats it.
            ForEach(contents.members, id: \.objectID) { member in
                MemberBalanceRow(
                    name: member.name ?? "Unnamed",
                    avatar: contents.avatars[member],
                    isLinked: member.cloudUserRecordName != nil,
                    balance: member.id.flatMap { contents.balances[$0] },
                    currencyCode: group.currency,
                    isMe: member == me
                )
                // A context menu rather than a row of its own: identity is
                // set once and never thought about again, and a permanent
                // "who am I" control would sit in the way of the balances
                // for the rest of the trip. Renaming and recolouring are
                // here for the same reason, and above the identity items
                // because they apply to every row — including the ones
                // already claimed by somebody else.
                .contextMenu {
                    Button("Edit Member", systemImage: "pencil") {
                        editTarget = EditTarget(
                            member: member,
                            avatar: contents.avatars[member]
                        )
                    }

                    if member == me {
                        Button("Not Me", systemImage: "person.slash") {
                            setIdentity(nil)
                        }
                    } else if CloudIdentity.isSomeoneElse(member) {
                        // Offered as a disabled row rather than hidden, so
                        // the answer to "why can't I pick this one?" is on
                        // screen instead of being an unexplained gap in a
                        // menu every other row has.
                        Button("Already Someone Else", systemImage: "person.fill.xmark") {}
                            .disabled(true)
                    } else {
                        Button("This Is Me", systemImage: "person.crop.circle.badge.checkmark") {
                            setIdentity(member)
                        }
                    }
                }
            }
            .onDelete { offsets in
                membersPendingDeletion = offsets.map { contents.members[$0] }
            }

            // A full-width row, not a glyph in the section header. This is the
            // only way to make the app usable on first launch, and a header
            // button gave it a ~20pt target well under the 44pt minimum.
            Button {
                showingAddMember = true
            } label: {
                Label("Add Member", systemImage: "person.badge.plus")
            }
        } header: {
            Text(.members)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                // Shown only until it has been answered — a hint that stays on
                // screen after you've acted on it is just clutter.
                if me == nil, !contents.members.isEmpty {
                    Text(.addressingTip)
                }

                // The roster looks complete whether or not it is, so the only
                // sign that somebody joined and never picked a name is this.
                if !unclaimedJoiners.isEmpty {
                    Text(unclaimedJoinersMessage)
                }
            }
        }
    }

    @ViewBuilder
    private func settleUpSection(_ contents: Contents) -> some View {
        if !contents.transfers.isEmpty {
            Section {
                ForEach(contents.transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        currencyCode: group.currency,
                        isMe: transfer.from.id == me?.id,
                        onSettle: { record(transfer, in: contents) },
                        onPartial: { partialTarget = transfer }
                    )
                }
            } header: {
                Text(.settleUp)
            } footer: {
                // Deliberately not "the fewest payments" — the calculator is
                // greedy, and the true minimum is NP-hard. See
                // `SettlementCalculator.transfers(settling:)`.
                Text(.settlementExplanation)
            }
        }
    }

    /// The log, one section per day.
    ///
    /// A week of receipts as one flat list is thirty rows with nothing to hold
    /// on to; the same rows under "Sat 12 July" are a trip somebody can find
    /// their way around. The date left the rows when it arrived in the headers —
    /// a date on every row under a header that already says it is noise sitting
    /// where the payer's name now goes.
    @ViewBuilder
    private func expensesSection(_ contents: Contents) -> some View {
        if contents.days.isEmpty {
            // Nothing at all until there is a roster. The summary block above
            // already says *Nothing spent yet*, and a grey *No expenses yet.*
            // under an Expenses header is that same sentence a second time, on
            // the one screen that has nothing else to look at — a brand-new
            // group announcing its own emptiness twice before offering anything
            // to do about it. `settleUpSection` above is the precedent: a
            // section with nothing to say does not appear.
            //
            // Once there are members the section returns carrying the *action*
            // rather than a placeholder, which is the rule the rest of this
            // screen follows and the one `membersSection` was fixed to obey.
            // The result is that each stage of a new group offers exactly one
            // next thing to do: add members, then add the first expense.
            if !contents.members.isEmpty {
                Section("Expenses") {
                    Button {
                        showingAddExpense = true
                    } label: {
                        Label("Add the First Expense", systemImage: "plus.circle")
                    }
                }
            }
        } else {
            ForEach(contents.days) { day in
                Section(day.title) {
                    ForEach(day.expenses, id: \.objectID) { expense in
                        expenseRow(expense, in: contents)
                    }
                    // Per day, because the offsets a section hands back index
                    // that section. Deleting against the whole log here would
                    // remove whatever sat at the same offset in it — the right
                    // row on the first day and the wrong one on every day
                    // after it.
                    .onDelete { offsets in
                        delete(at: offsets, from: day.expenses)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func expenseRow(_ expense: Expense, in contents: Contents) -> some View {
        // Payments are not editable: there is nothing in one to correct except
        // whether it happened, and that is what deleting it says. Ordinary
        // expenses open the form.
        if expense.isReimbursement {
            PaymentRow(expense: expense, currencyCode: group.currency)
                // Replaces the section's `onDelete` for this row alone.
                //
                // A payment is not something the user entered — it is an
                // assertion that a debt was settled — so the way back out of it
                // is an *undo*, and removing the record is merely how that is
                // implemented. Labelled "Delete", the only correction available
                // read as data loss: the first outside report of this came from
                // someone who marked a transfer paid by accident, swiped left
                // expecting to destroy something, and was surprised to find the
                // debt restored instead.
                //
                // Still `.destructive`, because a record does go away and the
                // red is honest about that. It is the word that was wrong.
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        undo(expense)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                    }
                }
        } else {
            Button {
                formTarget = FormTarget(expense: expense, mode: .edit)
            } label: {
                ExpenseRow(
                    expense: expense,
                    // From the same roster the members list is drawn from, not
                    // derived here: an expense whose payer showed one colour on
                    // one section and another two sections down would be worse
                    // than no colour at all.
                    avatar: expense.paidBy.map { contents.avatars[$0] },
                    currencyCode: group.currency
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the expense for editing")
            // Long-press rather than a swipe action or a button on the row:
            // repeating an expense is common enough to want and rare enough
            // that it shouldn't take up space in a list people mostly read.
            // Payments are left out — a settlement is recorded from the section
            // above, and paying the same debt twice is a mistake, not a
            // shortcut.
            .contextMenu {
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    formTarget = FormTarget(expense: expense, mode: .duplicate)
                }
            }
        }
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
            return String(localized: "\(expenseCount(resplit)) they were splitting gets divided between everyone left, so balances change.")
        case (_, 0):
            return String(localized: "This also removes \(expenseCount(removed)) they paid for, and recalculates everyone's balance.")
        default:
            return String(localized: "This also removes \(expenseCount(removed)) they paid for and re-splits \(expenseCount(resplit)) between everyone left. Balances change.")
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
        in contents: Contents
    ) {
        guard
            let payer = contents.person[transfer.from.id],
            let recipient = contents.person[transfer.to.id]
        else {
            errorMessage = "That member is no longer in this group."
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

    /// Counts as words. The agreement lives in the string catalog rather than
    /// here: English needs two forms, Polish needs four, and a `singular`/
    /// `plural` pair in Swift can only ever express the first of those.
    private func expenseCount(_ value: Int) -> String {
        String(localized: "\(value) expenses")
    }

    private func memberCount(_ value: Int) -> String {
        String(localized: "\(value) members")
    }

    /// "Ala and Bartek have joined but haven't picked a name yet."
    ///
    /// They/their throughout: CloudKit hands over a name, never a pronoun, and
    /// guessing one from a name gets it wrong for real people.
    private var unclaimedJoinersMessage: String {
        let names = unclaimedJoiners.formatted(.list(type: .and))
        return unclaimedJoiners.count == 1
            ? "\(names) has joined but hasn't picked their name from this list yet."
            : "\(names) have joined but haven't picked their names from this list yet."
    }
}

// MARK: - Form Target

/// Wraps the expense the form is opening on, and what it is opening for, so it
/// can drive `sheet(item:)`.
///
/// `Expense` cannot be `Identifiable` off its own `id`: every attribute is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` id would never
/// present. The object id is always there, and is exactly as stable as the
/// object itself — and the mode joins it so that duplicating the row you just
/// finished editing counts as a different sheet rather than the same one again.
private struct FormTarget: Identifiable {
    enum Mode: String {
        /// Rewrites the expense in place.
        case edit
        /// Leaves it alone and adds a copy.
        case duplicate
    }

    let expense: Expense
    let mode: Mode

    var id: String { "\(mode.rawValue)-\(expense.objectID.uriRepresentation())" }
}

/// The member being edited, with the avatar the row was already showing so the
/// sheet opens on it rather than re-deriving one.
///
/// Keyed on the object id for the same reason `FormTarget` is: `Person.id` is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` one would simply
/// never present.
private struct EditTarget: Identifiable {
    let member: Person
    let avatar: PersonAvatar

    var id: NSManagedObjectID { member.objectID }
}

// MARK: - Render Snapshot

/// Everything `GroupDetailView` reads off its group, gathered in one pass.
///
/// Ordinary computed properties would be re-evaluated at every mention, and
/// this screen mentions them a lot: the member list alone touched the balances
/// once per row, each time walking every expense and re-running the whole
/// settlement to pull out a single number.
/// One day of the log, as the expense list renders it.
///
/// Grouped in memory rather than through a `SectionedFetchRequest`, which wants
/// its section identifier to be a property Core Data can sort on — that would
/// have meant a stored day string on every `Expense`, a model version to add it,
/// a CloudKit schema promotion, and a value that has to be kept in step with the
/// date beside it forever. The fetch already hands these over sorted by date, so
/// the grouping is one pass with a comparison in it.
private struct ExpenseDay: Identifiable {
    let day: Date
    var expenses: [Expense]

    var id: Date { day }

    /// "Today", "Yesterday", or the date. Relative wording only where it is
    /// genuinely easier to place than a date — past yesterday, "3 weeks ago" is
    /// something to work out rather than read, and the weekday is what somebody
    /// reconstructing a trip actually remembers.
    ///
    /// `String(localized:)` rather than bare literals: this returns a `String`,
    /// and `Text(aString)` takes the *non*-localizing initializer — so the three
    /// relative words stayed English in every language while the dates beside
    /// them translated themselves through `formatted`. Caught in the Polish App
    /// Store screenshots, where the expense log read "Today" under a Polish
    /// heading.
    var title: String {
        let calendar = Calendar.current
        if day == .distantPast { return String(localized: "Undated") }
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }
}

@MainActor
private struct Contents {
    let members: [Person]
    /// The log, cut into days and newest first — the order the fetch hands it
    /// over in. The flat array it replaced had no readers left once the list
    /// went sectioned.
    let days: [ExpenseDay]
    let balances: [Participant.ID: Money]
    let transfers: [Transfer]
    let totalSpent: Money
    /// How many of the expenses are actual spending rather than settling up.
    let spendingCount: Int

    /// Where the money went, ready to draw — see `SpendBreakdown.slices(of:)`
    /// for the ordering rules and why they are in the package rather than here.
    ///
    /// Computed in the same pass everything else on this screen is, because a
    /// breakdown recomputed inside the summary section's body would walk the
    /// whole log again on every redraw — and this screen redraws on every tap.
    ///
    /// Reimbursements are excluded, as they are from `totalSpent`. A settle-up
    /// buys nothing, so a category breakdown that counted it would attribute
    /// money to a category twice: once when it was spent and once when somebody
    /// paid their share back.
    let spendByCategory: [SpendSlice<ExpenseCategory>]

    /// Members keyed by id, so recording a payment can get from the `Transfer`
    /// the settlement produced back to the `Person` the store needs to write.
    let person: [UUID: Person]

    /// One colour per member, resolved over the whole roster at once — see
    /// `RosterAvatars` for why it cannot be done a row at a time.
    let avatars: RosterAvatars

    /// The same numbers as a snapshot free of managed objects, ready to be
    /// rendered as shareable text. Built here because everything it needs is
    /// already in hand — it costs one more pass over `expenses`, not another
    /// settlement.
    let summary: GroupSummary

    /// Takes the roster and the log already sorted, because they arrive from
    /// fetch requests that sorted them in SQLite — see `Person.request(in:)`.
    init(group: ExpenseGroup, members roster: [Person], expenses log: [Expense]) {
        members = roster

        // A single pass, because `log` is already sorted by date descending —
        // see `Expense.request(in:)`. A record with no date at all gets its own
        // bucket rather than being dropped: it sorts last out of SQLite, so the
        // bucket lands at the bottom, and a row missing from the log would be
        // money missing from the screen.
        let calendar = Calendar.current
        days = log.reduce(into: []) { days, expense in
            let day = expense.date.map(calendar.startOfDay(for:)) ?? .distantPast
            if days.last?.day == day {
                days[days.count - 1].expenses.append(expense)
            } else {
                days.append(ExpenseDay(day: day, expenses: [expense]))
            }
        }

        person = Dictionary(
            roster.compactMap { member in member.id.map { ($0, member) } },
            uniquingKeysWith: { first, _ in first }
        )

        avatars = RosterAvatars(roster)

        let settlement = group.settlement(members: roster, expenses: log)
        balances = settlement.balanceByParticipant
        transfers = settlement.transfers
        totalSpent = settlement.totalSpent
        spendingCount = settlement.spendingCount

        summary = group.summary(from: settlement, expenses: log, memberCount: roster.count)

        spendByCategory = SpendBreakdown.slices(
            of: log
                .lazy
                .filter { !$0.isReimbursement }
                .map { (key: $0.category, amount: Money(amount: $0.amount)) }
        )
    }
}

// MARK: - Shared Summary

/// The group summary as something `ShareLink` can hand to the share sheet.
///
/// A `Transferable` wrapper rather than the finished `String`, because
/// `ShareLink` takes its item eagerly: passing the text itself would build the
/// whole message — a line per expense, formatted — on every redraw of this
/// screen, for a button most people tap once a trip. `ProxyRepresentation`
/// defers that to the tap.
///
/// Deferring is only safe because `GroupSummary` is a value snapshot with no
/// managed objects in it, so the closure can run whenever and on whatever actor
/// the share sheet chooses. Capturing anything Core Data owns here would be a
/// crash waiting for a slow share sheet.
private struct SharedSummary: Transferable {
    let summary: GroupSummary

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { $0.summary.text(strings: .localized) }
    }
}

// MARK: - Member Row

private struct MemberBalanceRow: View {
    let name: String
    let avatar: PersonAvatar
    /// Whether this member has been claimed by an iCloud account at all —
    /// yours included. They are a person on a phone of their own rather than a
    /// name somebody typed in on everyone's behalf.
    ///
    /// Deliberately not "somebody *else's* account". Showing it only for other
    /// people made the whole feature invisible to anyone testing with one
    /// device: the only row you can claim is your own, and your own row was
    /// already badged "You", so claiming it changed nothing on screen and there
    /// was no way to tell the link had been written.
    let isLinked: Bool
    let balance: Money?
    let currencyCode: String
    /// Whether this is the person holding the phone, which changes the caption
    /// from a statement about someone else into one about them.
    let isMe: Bool

    private var standing: Standing { Standing(balance: balance) }

    private var accessibleName: String {
        switch (isMe, isLinked) {
        case (true, true): "\(name), you, linked to iCloud"
        case (true, false): "\(name), you"
        case (false, true): "\(name), joined on iCloud"
        case (false, false): name
        }
    }

    var body: some View {
        // The balance and its caption sit in the *outer* stack, deliberately.
        // They used to share a `.firstTextBaseline` stack with the name, which
        // made the row two lines tall and pinned the name to the top of it —
        // while the avatar, a circle with no baseline to align to, centred
        // itself against the whole height. The name ended up riding several
        // points above the circle it belongs to. Everything here is centred
        // against everything else instead, so the name and its avatar agree.
        HStack(spacing: 12) {
            PersonIcon(avatar)

            // Still nested, for the spacing alone: the badges belong tight to
            // the name at 6pt, not at the 12 that separates the row's columns.
            HStack(spacing: 6) {
                Text(name)

                // A badge rather than replacing the name with "You": the name is
                // still how everyone else in the group refers to this person, and
                // dropping it makes the row harder to scan, not easier.
                if isMe {
                    Text(.youTheUser)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)  // carried by the label below
                }

                // Alongside the "You" capsule rather than instead of it, so
                // claiming your own row visibly does something. A glyph and not
                // a second capsule: "You" changes how the whole row reads,
                // where this only says the row has an account behind it, and
                // two capsules would stop the one that matters standing out.
                if isLinked {
                    Image(systemName: "checkmark.icloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)  // carried by the label below
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                switch standing {
                case .owes(let amount), .isOwed(let amount):
                    // Was `.caption`: the smallest text on the row was also
                    // the only number on it.
                    Text(amount.formatted(currencyCode: currencyCode))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(standing.tint)
                        .motionContentTransition(.numericText())
                case .settled:
                    Text(.settled)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(standing.caption(isMe: isMe))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: balance)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleName)
        .accessibilityValue(standing.accessibleValue(isMe: isMe, currencyCode: currencyCode))
    }
}

// MARK: - Transfer Row

private struct TransferRow: View {
    let transfer: Transfer
    let currencyCode: String
    /// Whether the payment is one *this* device's owner has to make.
    let isMe: Bool
    let onSettle: () -> Void
    /// Opens the sheet for handing over less than the whole transfer.
    let onPartial: () -> Void

    /// Wrapped, because this returns a `String` and `Text(payer)` resolves to
    /// the non-localizing initializer — the failure that has no warning and no
    /// stale key, because the string never had a key to begin with.
    private var payer: String {
        isMe ? String(localized: "You") : transfer.from.name
    }

    private var amount: String {
        transfer.amount.formatted(currencyCode: currencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            // One chooser over two *complete* candidates, amount included. The
            // fallback exists to need less width, so hoisting the amount out of
            // both would leave two spellings of the same row and never reach
            // the vertical layout at all.
            ViewThatFits(in: .horizontal) {
                // Preferred, while two names and an amount genuinely share a line.
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(payer).fontWeight(.medium)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transfer.to.name).fontWeight(.medium)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(namesLabel)

                    Spacer(minLength: 12)

                    amountButton
                }

                // Fallback for long names and accessibility text sizes, where the
                // single line used to truncate both names into uselessness.
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(payer) → \(transfer.to.name)")
                        .fontWeight(.medium)
                        .accessibilityLabel(namesLabel)

                    amountButton
                }
            }
            .font(.callout)

            // A visible button, not a swipe action. Settling up is the second
            // thing anyone comes to this screen to do, and hiding it behind a
            // gesture with no affordance means most people never find it.
            // `.borderless` keeps it a hit target of its own inside the row.
            //
            // Still the whole transfer, and still one tap. Paying in full is
            // the common case and the thing this screen exists for, so the
            // partial hangs off the amount instead of competing here.
            Button("Mark Paid", action: onSettle)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    isMe
                        ? "Mark your \(amount) payment to \(transfer.to.name) as paid"
                        : "Mark \(transfer.from.name)'s \(amount) payment to \(transfer.to.name) as paid"
                )
        }
    }

    /// Who pays whom, as one phrase.
    ///
    /// The amount used to be combined into this label. It is a control now, and
    /// a control folded into a combined element is a control VoiceOver cannot
    /// reach — the row would still read correctly and the action would be gone.
    /// The figure is not lost from the reading: it is the next element across.
    private var namesLabel: String {
        isMe
            ? String(localized: "You pay \(transfer.to.name)")
            : String(localized: "\(transfer.from.name) pays \(transfer.to.name)")
    }

    /// The figure, as the way in to paying part of it.
    ///
    /// Tinted rather than plain, because an affordance is the entire argument
    /// for this control existing here: the alternative was a long press, and
    /// the reasoning above about gestures nobody finds applies to a press as
    /// much as to a swipe. The accent colour, not the group's — a settlement
    /// figure is the one number on this screen that must not pick up a tint
    /// that could be read as a balance.
    ///
    /// A button rather than a one-item menu. The menu was the earlier guess and
    /// costs a tap to reach a single entry; the sheet it opens is prefilled
    /// with the full amount anyway, so tapping the figure loses nothing.
    private var amountButton: some View {
        Button(action: onPartial) {
            Text(amount).monospacedDigit()
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(
            isMe
                ? "Pay part of \(amount) to \(transfer.to.name)"
                : "Record part of \(transfer.from.name)'s \(amount) payment to \(transfer.to.name)"
        )
    }
}

/// One line of the spend breakdown: what it was, how much, and how much of the
/// total that is.
///
/// The bar earns its place by answering the question the figures alone don't —
/// *most of this trip was accommodation* is a glance, where four amounts in a
/// column is arithmetic. It is the group's own tint rather than a colour per
/// category: twelve categories would need twelve colours, the palette has eight
/// and deliberately excludes the two the balances already spend, and a chart
/// whose colours are reused every eight rows tells the reader nothing.
private struct BreakdownRow: View {
    let category: ExpenseCategory?
    let total: Money
    /// In `0...1`, and never `nan` — `SpendBreakdown` guards the zero-total case
    /// so this view does not have to.
    let fraction: Double
    let currencyCode: String

    @Environment(\.expenseGroupTint) private var tint

    private var name: String {
        category.map { String(localized: $0.label) } ?? String(localized: .categoryUncategorised)
    }

    private var amount: String { total.formatted(currencyCode: currencyCode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: category?.systemName ?? "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(name)
                    .font(.subheadline)

                Spacer(minLength: 12)

                Text(amount)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            // A capsule in a `GeometryReader`-free layout: the track is the full
            // width and the fill is a fraction of it, so nothing has to measure
            // anything. `.frame(height:)` on the stack keeps the reader from
            // stretching the row.
            GeometryReader { proxy in
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(0, proxy.size.width * fraction))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .leading) {
                        Capsule().fill(.fill.quaternary)
                    }
            }
            .frame(height: 4)
        }
        // One element, one sentence. Read child by child this is a glyph, a
        // word, a figure and an unlabelled bar — where the bar is the one part
        // with nothing to say out loud.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(amount)")
    }
}

/// The tint of the group being looked at, so a row deep in the hierarchy can
/// carry it without every intermediate view passing it down.
///
/// Defaults to `.accentColor`, which is what a preview or a stray call site
/// gets — never a hardcoded blue that would silently disagree with a group.
private struct ExpenseGroupTintKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    fileprivate var expenseGroupTint: Color {
        get { self[ExpenseGroupTintKey.self] }
        set { self[ExpenseGroupTintKey.self] = newValue }
    }
}

// MARK: - Expense Row

private struct ExpenseRow: View {
    let expense: Expense
    /// The payer's avatar, so the colour that identifies them on the members
    /// list identifies their spending too — the log becomes scannable by whose
    /// it is before a word of it is read.
    ///
    /// Optional because `paidBy` is: an expense whose payer is mid-sync still
    /// has to draw a row, and `SettlementBridge` already drops it from the
    /// maths. It falls back to the grey no-name circle rather than to a gap,
    /// which would break the column the rest of the list lines up on.
    let avatar: PersonAvatar?
    let currencyCode: String

    /// The title, or `nil` for an expense saved without one.
    ///
    /// Blank and absent are the same thing here. `GroupStore` stores an empty
    /// title as `nil`, but a record synced from a client built before titles
    /// were optional can still carry `""` — and a row testing only for `nil`
    /// would draw an empty line for it.
    private var title: String? {
        let text = expense.title?.trimmingCharacters(in: .whitespaces) ?? ""
        return text.isEmpty ? nil : text
    }

    private var payer: String { expense.paidBy?.name ?? "?" }

    /// VoiceOver gets no colour from the circle and would otherwise hear a bare
    /// name with nothing saying what it is doing there.
    private var accessiblePayer: String {
        "Paid by \(expense.paidBy?.name ?? "unknown")"
    }

    /// The category glyph, drawn beside whatever leads the row.
    ///
    /// A glyph and not the word. The log is scanned rather than read, the row
    /// already spends its width on a title, a payer and two figures, and the
    /// form's menu is where the glyph is learned — it lists every category with
    /// its name beside it. Nothing is drawn at all for an unfiled expense: a
    /// placeholder tag in that column would make "no category" look like a
    /// category, and most expenses will never have one.
    ///
    /// `.secondary` and never tinted. Every colour in this list already belongs
    /// to a person or to a balance, and a third colour system competing with
    /// those is how a row stops being scannable.
    @ViewBuilder
    private var categoryMark: some View {
        if let category = expense.category {
            Image(systemName: category.systemName)
                // `.caption` first time round, which was too quiet to find: the
                // first person to use categories on real expenses reported not
                // being able to see them anywhere. Level with the title it sits
                // beside, still `.secondary` so it labels the row rather than
                // competing with it.
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Sized so a wide glyph and a narrow one leave the titles
                // beside them starting in the same place.
                .frame(width: 18)
                .accessibilityLabel(Text(category.label))
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            PersonIcon(avatar ?? PersonAvatar(initials: nil, color: .gray), size: 26)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    HStack(spacing: 6) {
                        categoryMark
                        Text(title)
                            .font(.body)
                    }

                    // Three lines once — title, date, "Paid by X". The date
                    // moved to the day header above and the circle carries the
                    // payer, which leaves the name as the one thing still worth
                    // a second line: initials are ambiguous and a colour has to
                    // be learned.
                    //
                    // `.secondary`, not `.tertiary`: tertiary is for
                    // decoration, and who paid is the point of the row.
                    Text(payer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(accessiblePayer)
                } else {
                    // An untitled expense leads with the payer rather than with
                    // a filler word. "Untitled" says nothing, and says it again
                    // on every row once titles are optional — where the payer
                    // and the amount together are already a complete sentence.
                    // `PaymentRow` in this same list has established that a
                    // one-line row reads fine among two-line ones.
                    HStack(spacing: 6) {
                        categoryMark
                        Text(payer)
                            .font(.body)
                            .accessibilityLabel(accessiblePayer)
                    }
                }
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                    .font(.callout)
                    .monospacedDigit()

                // What was actually handed over, for expenses paid abroad. The
                // group's own figure stays the prominent one — it is the number
                // the balances are built from — with this as its receipt.
                if let foreign = expense.foreignAmount {
                    Text(foreign.formatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Payment Row

/// A settling-up payment in the expense list.
///
/// Rendered as a sentence rather than a title and an amount, because that is
/// what it is: money that moved between two people and bought nothing. It sits
/// in the same list as the expenses so it can be deleted the same way — which
/// is the only undo a mis-tapped "Mark Paid" needs.
private struct PaymentRow: View {
    let expense: Expense
    let currencyCode: String

    /// The width of an expense row's avatar, tracked so the two kinds of row in
    /// this list start their text on the same column. Same base, same
    /// relative-to and same cap as `PersonIcon`, so they stay together at every
    /// type size rather than only at the default one.
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 26

    private var sentence: String {
        let payer = expense.paidBy?.name ?? "?"
        let recipient = expense.reimbursementRecipient?.name ?? "?"
        return "\(payer) paid \(recipient)"
    }

    var body: some View {
        HStack(spacing: 12) {
            // A bare glyph rather than a circle: a payment has two people in it
            // and no single colour to carry, and giving it an avatar-shaped mark
            // would make it read as somebody's expense.
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: min(iconSide, 26 * 1.4))
                .accessibilityHidden(true)

            // One line now the day header carries the date. A payment has no
            // title to pair a date with, so dropping it left nothing behind.
            Text(sentence)
                .font(.callout)

            Spacer(minLength: 12)

            // Secondary, unlike an expense amount: this figure is not part of
            // what the trip cost, and giving it the same weight as a real
            // expense would suggest it was.
            Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(sentence) \(Money(amount: expense.amount).formatted(currencyCode: currencyCode))"
        )
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: PersistenceController.previewGroup)
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}
