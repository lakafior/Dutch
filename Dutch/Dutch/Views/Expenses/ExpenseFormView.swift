/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import CoreData
import DutchKit

/// What a member pays, as a percentage of a full share.
///
/// Relative and deliberately not a division of the bill: the percentages across
/// a split do not add up to 100, and are not meant to. Six people with one
/// 51%-off fare is `100 × 5` and `49`, which comes to 549%.
private enum Share {
    /// A full share, and where every member starts.
    static let full = 100

    /// Offered in the menu. Halves cover a couple sharing a hotel room and
    /// children at half price, which between them are most of what an uneven
    /// split is ever for; anything else goes through "Other…".
    static let presets = [100, 75, 50, 25]

    /// 200% is somebody eating for two. Below 1% a share rounds to nothing on
    /// any realistic bill, and 0 is what deselecting the row already means.
    static let range = 1 ... 200
}

/// What one row of the split is currently saying.
///
/// Two ways of answering the same question, never one field doing both: `50`
/// cannot mean half a share on one row and fifty złoty on the next, and a
/// control where it might is one nobody can read at a glance. A row is in one
/// mode or the other, and switching is a menu choice rather than a guess made
/// from what was typed.
private enum RowShare: Equatable {
    /// A percentage of a full share — the shipped behaviour, unchanged.
    case percent(Int)
    /// A figure the receipt already gave, in the currency being typed in.
    case exact(Money)
}

/// Sheet for adding a new expense to a group, or correcting an existing one.
///
/// One form for both, deliberately. The alternative the app used to force was
/// delete-and-re-enter, which on a shared group means everyone else watches an
/// expense vanish and reappear over CloudKit — and gives them a window in which
/// the balances are simply wrong.
struct ExpenseFormView: View {
    let group: ExpenseGroup

    /// The expense being corrected, or `nil` when adding a new one. Everything
    /// that differs between the two modes reads from this.
    private let editing: Expense?

    /// Whether this is a copy of an existing expense rather than a blank one.
    ///
    /// Separate from `editing` because a duplicate saves like an add — a new
    /// record, dated now — but is seeded like an edit, so neither flag alone
    /// describes it.
    private let isDuplicate: Bool

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    /// Held as text rather than a `Double` so the field can start genuinely
    /// empty. Bound to a number it showed a literal `0` that `isValid` then
    /// rejected — a form that looks filled in and refuses to save.
    @State private var amountText: String
    /// The currency the amount is being *entered* in, which is not necessarily
    /// the one the group settles in.
    @State private var currencyCode: String
    /// Units of `currencyCode` per one unit of the group's currency. Text for
    /// the same reason `amountText` is.
    @State private var rateText: String
    /// Who put money in. A set rather than one person because more than one
    /// can, and one is simply the common size of it.
    ///
    /// Several payers are offered only when *adding*, which includes a
    /// duplicate. An edit rewrites one record in place, so letting it grow a
    /// second payer would mean a save that splits the row in two — a form that
    /// silently creates records is worse than one that asks you to add the
    /// second yourself.
    @State private var selectedPayers: Set<Person> = []
    /// What each payer put in, once there is more than one.
    ///
    /// Against the **tipped** figure, unlike `exactAmounts` on the sharer side,
    /// and the asymmetry is real rather than an oversight: a sharer's exact
    /// figure is a line off a receipt and receipts are printed before the tip,
    /// while a payer's is cash that actually changed hands and the tip was in
    /// it. Both are still relative once stored — see `GroupStore.addExpenses` —
    /// so the conversion carries through either way.
    @State private var payerAmounts: [Person: Money] = [:]
    /// Whether the rows under **Paid By** select one payer or several.
    ///
    /// Off, and a tap *replaces* the payer. Correcting who paid is far and away
    /// the commoner action — several people putting money in is the rare one —
    /// and multi-select made the common case cost two taps: pick the right
    /// person, then unpick the wrong one. A mode nobody asked for should not
    /// tax the tap everybody makes.
    ///
    /// The same shape as `Uneven split` one section below, deliberately: this
    /// form already teaches that a toggle at the foot of a section changes what
    /// the rows in it do, and that is a lesson better taught twice than twice
    /// over in two different ways.
    @State private var severalPayers = false
    /// The payer whose contribution is being typed, and the text of it.
    @State private var payerTarget: Person?
    @State private var payerText = ""
    @State private var selectedParticipants: Set<Person> = []
    /// What each member pays as a percentage of a full share, used only while
    /// `splitsEvenly` is off. A member with no entry pays a full 100%.
    ///
    /// Relative, not a division of the bill: these do not add up to 100. Six
    /// people, one of them on a 51%-off fare, is five entries of `100` and one
    /// of `49` — which sums to 549% and is exactly right. Nothing shows the
    /// user that total; the rows show złoty amounts, and those do add up.
    @State private var shares: [Person: Int] = [:]
    /// Members whose figure came off the receipt instead, in the currency the
    /// amount above is being typed in.
    ///
    /// A member is in exactly one of this and `shares` — presence here is what
    /// puts the row in exact mode, which is why switching modes removes the
    /// entry rather than leaving a stale figure behind it.
    ///
    /// Deliberately the *typed* currency and *before* the tip, matching the
    /// field above it: these are the lines on the receipt. The weighting they
    /// become is relative, so a tip and a conversion both carry through
    /// proportionally — everybody pays their item plus their share of the tip,
    /// which is what a tip on an itemised bill means.
    @State private var exactAmounts: [Person: Money] = [:]
    @State private var splitsEvenly: Bool
    /// The member whose share is being typed in by hand, and the text of it.
    @State private var customTarget: Person?
    @State private var customText = ""
    /// The member whose exact figure is being typed in, and the text of it.
    /// Separate from `customTarget` because the two alerts take different
    /// keyboards and mean different things by the same digits.
    @State private var exactTarget: Person?
    @State private var exactText = ""
    /// What it was for, or `nil` for the expense nobody filed. Optional in the
    /// state as well as in the model: a category is a thing to leave blank, and
    /// defaulting it to *Other* would fill the log with a word meaning "the
    /// user didn't say" while looking like they had.
    @State private var category: ExpenseCategory?

    /// When the expense happened. Never optional here: the picker cannot
    /// produce "no date", and the log's dateless bucket is for records caught
    /// mid-sync, not for something a user chose.
    @State private var date: Date
    /// What the picker started at, so `save` can tell a deliberate change from
    /// an untouched field. Passing the date back unconditionally would stamp
    /// today onto a dateless record the moment somebody edited its title.
    private let seedDate: Date

    /// Tip, tax or service charge — a percentage of the amount or a flat sum,
    /// never both.
    ///
    /// Always starts at none, including on an edit and on a duplicate: the tip
    /// is folded into the stored amount, so the figure in the field above is
    /// already the tipped one, and re-offering it would apply it a second time.
    @State private var tip: Tip = .none
    @State private var showingCustomTip = false
    @State private var customTipText = ""
    /// The flat sum being typed. Separate from `customTipText` for the reason
    /// the two share alerts are separate: the same digits mean a percentage in
    /// one and money in the other, and a field that might be either is the
    /// ambiguity `Tip` has two cases to avoid.
    @State private var flatTipText = ""
    @State private var showingFlatTip = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    /// Whether the currency list is on screen.
    ///
    /// A pushed destination driven by a flag rather than a `NavigationLink`,
    /// because the control that opens it now shares a row with the amount
    /// field — and a `NavigationLink` in a `Form` claims the whole row, which
    /// would mean tapping the number to type in it pushed a screen instead.
    @State private var showingCurrencyPicker = false

    /// The nearby-places service, observed so the button appears and disappears
    /// with the setting and with the system's answer — a form left open while
    /// permission is revoked in Settings.app must not keep offering it.
    @ObservedObject private var nearby = NearbyPlaces.shared
    @State private var showingNearby = false

    /// The place this expense was attached to, if one was picked.
    ///
    /// Kept separately from `title` even though a pick can write both, because
    /// the two answer different questions the moment either is edited: the
    /// title is what this expense is *called* — "Anna's birthday" — and this is
    /// where it happened. Storing only the title would make the second fact
    /// disappear the first time somebody rewords the first.
    @State private var attached: ExpensePlace?

    /// The foreign currencies this group has already spent in, newest first.
    ///
    /// Read once at construction rather than per render: the picker's option
    /// list is rebuilt on every keystroke in the amount field, and this would
    /// otherwise hit `UserDefaults` each time for a value that cannot change
    /// while the form is open.
    private let recentCurrencies: [String]

    /// A new expense, with every selection seeded from the state the form would
    /// otherwise make the user re-enter on each one.
    ///
    /// Done in `init` rather than `.task` so the sheet is never briefly drawn
    /// with nothing selected, and so a later re-render can't re-seed over an
    /// edit in progress — `@State` keeps the value from first construction.
    init(group: ExpenseGroup) {
        self.group = group
        self.editing = nil
        self.isDuplicate = false

        let roster = Self.roster(of: group)
        // Splitting across everyone is what the app is for; "nobody" was never
        // a useful starting point, and cost a tap per member to escape.
        _selectedParticipants = State(initialValue: Set(roster))
        _selectedPayers = State(
            initialValue: Set(ExpenseDefaults.lastPayer(in: group, among: roster).map { [$0] } ?? [])
        )
        _title = State(initialValue: "")
        _amountText = State(initialValue: "")
        _splitsEvenly = State(initialValue: true)

        let now = Date()
        _date = State(initialValue: now)
        self.seedDate = now
        _category = State(initialValue: nil)
        _attached = State(initialValue: nil)

        // Mid-trip, the next expense is almost always in the same currency as
        // the last one, at the same rate. Entering ten Polish receipts should
        // cost one rate lookup, not ten.
        let currency = ExpenseDefaults.lastCurrency(in: group) ?? group.currency
        _currencyCode = State(initialValue: currency)
        _rateText = State(initialValue: Self.rateText(for: currency, in: group))
        self.recentCurrencies = ExpenseDefaults.recentCurrencies(in: group)
    }

    /// An existing expense, seeded from what was recorded rather than from the
    /// device's defaults.
    init(editing expense: Expense, in group: ExpenseGroup) {
        self.init(group: group, seededFrom: expense, editing: expense)
    }

    /// A new expense carrying over everything an existing one already had.
    ///
    /// Four people taking turns at the bar enter the same title, the same
    /// amount and the same split four times over, and only the payer differs —
    /// which is also the one field `ExpenseDefaults.lastPayer` gets reliably
    /// wrong, since in a round the person who paid last is precisely the person
    /// not paying now. Copying what the user already entered beats guessing at
    /// a cleverer prefill.
    init(duplicating expense: Expense, in group: ExpenseGroup) {
        self.init(group: group, seededFrom: expense, editing: nil)
    }

    /// The seeding both of the above share.
    ///
    /// A foreign expense reopens in the currency it was *entered* in, not the
    /// group's. The stored `amount` is the converted figure, so showing that as
    /// the starting point would mean someone who came to fix a typo in the
    /// title saves a euro total back into a złoty field.
    private init(group: ExpenseGroup, seededFrom expense: Expense, editing: Expense?) {
        self.group = group
        self.editing = editing
        self.isDuplicate = editing == nil

        _title = State(initialValue: expense.title ?? "")
        // Left blank on a duplicate, and it is the only field that is: the
        // payer is the thing the user came to change, and carrying the original
        // over would let a whole round be logged against the wrong person with
        // one tap on Save. An empty picker keeps Save disabled until they say.
        _selectedPayers = State(initialValue: editing == nil ? [] : Set([expense.paidBy].compactMap { $0 }))
        _selectedParticipants = State(initialValue: (expense.splitAmong as? Set<Person>) ?? [])

        if let foreign = expense.foreignAmount {
            _currencyCode = State(initialValue: foreign.currencyCode)
            _amountText = State(initialValue: DecimalInput.text(foreign.amount))
            _rateText = State(initialValue: DecimalInput.text(foreign.rate, precision: 6))
        } else {
            _currencyCode = State(initialValue: group.currency)
            _amountText = State(initialValue: DecimalInput.text(expense.amount))
            _rateText = State(initialValue: "")
        }

        // An edit reopens on the day it was recorded; a duplicate starts today.
        // The duplicate is the interesting half: it carries everything else
        // over, but a round logged tonight from last Tuesday's receipt would
        // land in Tuesday's bucket — which is the exact filing error this field
        // exists to prevent, reintroduced by the prefill meant to save typing.
        let seeded = editing == nil ? Date() : (expense.date ?? Date())
        _date = State(initialValue: seeded)
        self.seedDate = seeded

        // Carried by a duplicate as well as an edit, unlike the date. Four
        // people taking turns at the bar are filing four *Drinks*, and the
        // category is exactly the kind of retyping Duplicate exists to save —
        // where the date is the one field whose carried-over value would be
        // silently wrong.
        _category = State(initialValue: expense.category)

        // Carried by an edit, and deliberately *not* by a duplicate. A place is
        // a claim about where somebody physically was, and the second round —
        // bought an hour later, possibly in the next bar — has not earned it.
        // Everything else here is a prefill that costs a correction when it is
        // wrong; this one would be a wrong fact, synced.
        _attached = State(initialValue: editing == nil ? nil : ExpensePlace(expense))

        // An expense with no stored weighting is an even split, and a uniform
        // weighting is stored as none at all — so the toggle starts on exactly
        // when there is something uneven to show.
        let weights = expense.shareWeights
        _splitsEvenly = State(initialValue: weights.isEmpty)
        _shares = State(initialValue: Self.shares(from: weights, in: group))
        _exactAmounts = State(
            initialValue: Self.exactAmounts(
                from: weights,
                markedBy: expense.exactShareIDs,
                // The basis the rows are typed against, which is the field
                // above: the foreign figure when there is one, otherwise the
                // stored amount. Seeding from the *slices* rather than from the
                // stored weights is what makes this round-trip — a bill entered
                // with a tip stored weights summing to the pre-tip figure, and
                // re-showing those against a field that now holds the tipped
                // total would leave a remainder the user never created and
                // Save disabled on an expense they only opened to rename.
                of: Money(amount: expense.foreignAmount?.amount ?? expense.amount),
                in: group
            )
        )
        self.recentCurrencies = ExpenseDefaults.recentCurrencies(in: group)
    }

    // MARK: - Seeding

    private var isEditing: Bool { editing != nil }

    /// Says which of the three the sheet is, so a duplicate can't be mistaken
    /// for an edit of the row it was opened from — the difference being whether
    /// the original survives.
    private var navigationTitle: String {
        if isEditing { return "Edit Expense" }
        return isDuplicate ? "Duplicate Expense" : "Add Expense"
    }

    /// Weights come back keyed by id; the form works in `Person`, which is what
    /// the rows and the selection are built from.
    private static func shares(from weights: [UUID: Int], in group: ExpenseGroup) -> [Person: Int] {
        guard !weights.isEmpty else { return [:] }

        return roster(of: group).reduce(into: [:]) { result, member in
            if let id = member.id, let weight = weights[id] {
                result[member] = weight
            }
        }
    }

    /// The rows that were typed as cash, as the figures they represent.
    ///
    /// Reconstructed by dividing the basis the way the stored weighting says
    /// to, rather than by reading the weights as cents directly. Those two
    /// agree exactly whenever the expense had no tip and no conversion, and
    /// where they don't, this one is right: the weights are relative, so what
    /// the member is actually being charged is their slice.
    private static func exactAmounts(
        from weights: [UUID: Int],
        markedBy marked: Set<UUID>,
        of basis: Money,
        in group: ExpenseGroup
    ) -> [Person: Money] {
        guard !weights.isEmpty, !marked.isEmpty else { return [:] }

        let slices = Dictionary(
            SettlementCalculator.slices(of: basis, among: weights)
                .map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        return roster(of: group).reduce(into: [:]) { result, member in
            if let id = member.id, marked.contains(id), let slice = slices[id] {
                result[member] = slice
            }
        }
    }

    /// The remembered rate for a currency, as the text field wants it.
    private static func rateText(for currencyCode: String, in group: ExpenseGroup) -> String {
        guard
            currencyCode != group.currency,
            let rate = ExpenseDefaults.lastRate(in: group, currencyCode: currencyCode)
        else { return "" }

        return DecimalInput.text(rate, precision: 6)
    }

    private var store: GroupStore { GroupStore(context: context) }

    private var members: [Person] { Self.roster(of: group) }

    private static func roster(of group: ExpenseGroup) -> [Person] {
        (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        // Taken once and passed down. Read as a computed property this would be
        // recomputed at every mention — and this form mentions it once per
        // member row, each pass sorting the sharers and re-splitting the whole
        // amount.
        let slices = slicePreview

        // The roster for the same reason, and it is mentioned more often than
        // the slices are: twice in the payer picker, twice in the split section,
        // and twice more in `allSelected` behind the Everyone button. Each of
        // those was pulling the members out of a relationship set and sorting
        // them again.
        let roster = members

        // Resolved over the whole roster, so a member's colour here is the one
        // the group screen gave them — an avatar that changed between the two
        // screens would be worse than no avatar at all.
        let avatars = RosterAvatars(roster)

        NavigationStack {
            // The order is the whole point of this screen's last revision, and
            // it is worth stating so it is not tidied back: the figure and
            // everything that changes it come first, then the two questions a
            // balance is actually made of, and the prefilled rows nobody
            // touches on the ordinary path come last.
            //
            // Details used to sit second, which meant a round of drinks split
            // evenly — the commonest expense there is — scrolled past six rows
            // it would never answer to reach the two it had to.
            Form {
                amountSection
                paidBySection(roster, avatars)
                splitAmongSection(slices, roster, avatars)
                detailsSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // "Save" in both modes. The title above already says which
                    // one this is, and the UI tests reach for this button by
                    // name — a label that changes with the mode would make the
                    // add flow's assertions depend on state they never set.
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            // A rate is only meaningful for the currency it was entered for, so
            // switching currency replaces it rather than carrying 4.4111 over
            // from złoty to forint — which would convert, and be wrong by two
            // orders of magnitude, with nothing on screen looking amiss.
            .onChange(of: currencyCode) { _, newCode in
                rateText = Self.rateText(for: newCode, in: group)
            }
            .onChange(of: selectedPayers) { previous, current in
                // Most of the time a payer also shares the expense, so
                // preselect them. They can still be toggled back off — which is
                // why only the newly added ones are inserted, rather than the
                // whole set re-added on every change.
                for payer in current.subtracting(previous) {
                    selectedParticipants.insert(payer)
                }
                // A contribution belonging to somebody no longer paying would
                // keep counting against the total, exactly as a stale share
                // would on the other side of the form.
                for payer in previous.subtracting(current) {
                    payerAmounts[payer] = nil
                }
            }
            // One haptic per change to the selection as a whole. Per-row
            // feedback would fire six times at once on "Everyone".
            .sensoryFeedback(.selection, trigger: selectedParticipants)
            // Picking a payer is a tap on a row that looks like those, so it
            // has to feel like one. A second modifier rather than a combined
            // trigger, because the payer is usually already a sharer and the
            // set above then doesn't change at all — folding them together
            // would leave the commonest tap on this screen silent. When the
            // payer *wasn't* sharing, both fire in the same frame, which the
            // haptic engine renders as the one tap it was.
            .sensoryFeedback(.selection, trigger: selectedPayers)
            .alert("Custom Share", isPresented: customBinding) {
                TextField(String(localized: .customSharePercent), text: $customText)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { customTarget = nil }
                Button(.setCustomShare, action: applyCustomShare)
            } message: {
                Text(.partialPercentageExplanation)
            }
            // A second alert rather than a mode inside the first: the two take
            // different keyboards, and the same digits mean different things in
            // each. Sharing one field is exactly the ambiguity `RowShare` was
            // split in two to avoid.
            .alert("Exact Amount", isPresented: exactBinding) {
                // Decimal, not the number pad the percentage field uses — the
                // whole point is a figure off a receipt, and receipts have
                // minor units.
                TextField(String(localized: .exactAmountField), text: $exactText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { exactTarget = nil }
                Button(.setExactAmount, action: applyExactAmount)
            } message: {
                Text(.exactAmountExplanation)
            }
            .alert("Contribution", isPresented: payerAmountBinding) {
                TextField(String(localized: .exactAmountField), text: $payerText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) { payerTarget = nil }
                Button(.setExactAmount, action: applyContribution)
            } message: {
                Text(.contributionExplanation)
            }
            .alert("Custom Tip", isPresented: $showingCustomTip) {
                // Decimal rather than number pad: 12.5% is a real service
                // charge, and a number pad makes it unenterable.
                TextField(String(localized: .customTipPercent), text: $customTipText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {}
                Button(.setCustomTip, action: applyCustomTip)
            } message: {
                Text(.tipExplanation)
            }
            // A second alert rather than a mode inside the first, on the same
            // reasoning that split Custom Share from Exact Amount: the two mean
            // different things by the same digits, and the field's own prompt
            // — Percent against Amount — is the only thing on screen saying
            // which was asked for.
            .alert(Text(.tipAmountTitle), isPresented: $showingFlatTip) {
                TextField(String(localized: .exactAmountField), text: $flatTipText)
                    .keyboardType(.decimalPad)
                Button("Cancel", role: .cancel) {}
                Button(.setExactAmount, action: applyFlatTip)
            } message: {
                Text(.tipAmountExplanation)
            }
            .errorBanner($errorMessage)
            .sheet(isPresented: $showingNearby) {
                NearbyPlacesSheet(onPick: adopt)
            }
            .navigationDestination(isPresented: $showingCurrencyPicker) {
                CurrencyPicker(
                    selection: $currencyCode,
                    inUse: inUseCurrencies,
                    all: Locale.commonISOCurrencyCodes
                )
            }
            .task {
                // The amount, not the title. The amount is the one field this
                // screen cannot be saved without, and it raises the decimal pad
                // — where starting in the title raised a full keyboard on a
                // form whose entire purpose is a number, and asked for the one
                // thing that is now optional.
                //
                // Only on a blank form. Opening the keyboard on an edit — or on
                // a duplicate — puts a cursor in a figure the user most likely
                // came to keep.
                amountFocused = !isEditing && !isDuplicate
            }
        }
    }

    // MARK: - Sections

    /// The step down in weight given to every row the form can be saved
    /// without.
    ///
    /// The amount is what an expense is; the rate, the tip, the place, the date
    /// and the category are rows that either already have an answer when the
    /// sheet opens or are absent until something is attached. In the ordinary
    /// case — a single-currency group buying a round today with no service
    /// charge on it — not one of them is touched. Drawn at the same weight as
    /// the amount, they read as a set of equally important questions on a form
    /// whose entire purpose is one number.
    ///
    /// The rule used to be narrower: *qualifies the amount rather than being
    /// it*, which was true of the first three and made the date look like an
    /// exception when it arrived. It isn't one. What they have in common is
    /// that they are prefilled or optional, and that is the property worth
    /// drawing — a required field the user must answer and a defaulted one they
    /// may ignore should not carry the same weight.
    ///
    /// One step of the type scale, not a hand-picked size, so Larger Text keeps
    /// scaling all of it. Defined here rather than repeated at the call sites
    /// because the decision is "these are secondary", and it should be possible
    /// to change that in one place.
    private func qualifier<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().font(.subheadline)
    }

    /// The figure, and everything that changes what it means.
    ///
    /// Headerless, and first. The navigation title already says which of the
    /// three things this sheet is, and a header over a screen whose entire
    /// purpose is one number is a label nobody needed.
    ///
    /// Amount leads because it is the only field Save depends on — the cursor
    /// has started here since the first-feedback batch, and the reading order
    /// now agrees with the typing order instead of contradicting it. The rate
    /// follows immediately because a foreign amount is not a figure at all
    /// until it has one.
    ///
    /// Then the title, and *then* the tip — not the other way round, which is
    /// how this was first written. Amount and title are the two rows a person
    /// actually fills in; the tip is an adjustment most expenses never carry,
    /// and putting it between them is the same mistake this reorder exists to
    /// fix, only smaller. Last also puts it directly above the footer that
    /// says a tip is included, which is where it wants to be read.
    ///
    /// The place is here rather than in **Details** even though it reads like
    /// a detail, and that is deliberate. It exists only as the consequence of
    /// tapping **Nearby** on the title row directly above it, and the whole
    /// feature was made acceptable on the condition that the attachment is
    /// visible at the moment it is made. Two sections down it would be off
    /// screen at exactly that moment.
    private var amountSection: some View {
        Section {
            amountRow
            rateRow

            HStack(spacing: 12) {
                // Named as optional in the placeholder, because nothing else on
                // screen says so: Save stays enabled with it blank, and a field
                // people believe is required is one they stop to fill in.
                TextField("Title (optional)", text: $title)
                    .submitLabel(.next)
                    // Pinned, so the placeholder above is free to change wording
                    // without breaking the UI tests that reach for this field.
                    .accessibilityIdentifier("Title")

                if nearby.isOffered {
                    nearbyButton
                }
            }

            placeRow
            tipRow
        } footer: {
            // Echoes back exactly what will be stored, which is the only way
            // the user can catch a mis-parsed separator — or a rate entered
            // upside down — before saving.
            //
            // Directly under the three rows that decide the figure, which is
            // where it belongs and where it now is: it used to footer the
            // Details section because Currency and the rate lived there, and
            // moving those up here brought it with them.
            if let summary = savesAsSummary {
                Text(summary)
                    .motionContentTransition(.numericText())
            }
        }
    }

    /// Offers the places around you as a title — and only ever when asked.
    ///
    /// Icon-only, which is unusual for this app and is the point: the row's
    /// width belongs to the field, and nobody sees this button without having
    /// turned it on in Settings first, so it is not carrying the job of
    /// explaining itself. The sheet it opens is titled in words.
    private var nearbyButton: some View {
        Button {
            showingNearby = true
        } label: {
            Image(systemName: "location")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Otherwise the whole row takes the tap: a `Button` inside a `Form` row
        // renders as one tappable cell, and typing in the field would open the
        // sheet.
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Nearby"))
        .accessibilityIdentifier("Nearby")
    }

    /// The two rows that already have an answer when the sheet opens.
    ///
    /// Last, and that is the change this section exists to record. It used to
    /// sit second, on the reasoning that the rate is required for a foreign
    /// expense and that the footer beneath it was the only place a bad rate
    /// could be caught — both true, and both arguments about Currency, the
    /// rate and the tip rather than about Date and Category. Those three moved
    /// up to the figure they qualify and took the footer with them, which
    /// leaves nothing here that Save can ever depend on.
    ///
    /// Deliberately **not** collapsed behind a chevron. The date's whole value
    /// is that a user adopting the app mid-trip can *see* that backdating
    /// exists; hiding the row takes back the reason it was added, and a section
    /// of two rows saves nothing worth that.
    private var detailsSection: some View {
        Section {
            dateRow
            categoryRow
        } header: {
            Text(.expenseDetails)
        }
    }

    /// What it was for.
    ///
    /// A `Menu`-backed `Picker` rather than the symbol grid `AppearancePicker`
    /// uses. A group's symbol is decoration chosen by eye, so a grid of glyphs
    /// is the right control for it; a category has a *name*, and twelve glyphs
    /// with no words under them would ask the user to guess whether the bolt
    /// means electricity or fast — which is exactly the ambiguity a category is
    /// supposed to remove.
    ///
    /// `None` is first and is a real choice, not a placeholder: an expense
    /// nobody filed has to be reachable back from one that was, or clearing a
    /// category means deleting the expense and entering it again.
    private var categoryRow: some View {
        qualifier {
            Picker(selection: $category) {
                Text(.categoryNone).tag(ExpenseCategory?.none)

                ForEach(ExpenseCategory.allCases) { option in
                    // Glyph *and* word in the menu, so the row's bare glyph is
                    // learnable — this is the only screen that says which is
                    // which.
                    Label {
                        Text(option.label)
                    } icon: {
                        Image(systemName: option.systemName)
                    }
                    .tag(ExpenseCategory?.some(option))
                }
            } label: {
                Text(.category)
                    .foregroundStyle(.secondary)
            }
            .pickerStyle(.menu)
        }
    }

    /// When it happened.
    ///
    /// The first row of **Details**, at the foot of the form. It was directly
    /// under the amount for as long as Details sat second, on the reasoning
    /// that nothing goes above the one field Save depends on; that reasoning
    /// survives the move, because nothing still does. This is simply the least
    /// often touched row on the screen, and it is now filed with the other one.
    ///
    /// A `qualifier`, like the tip and the rate: the form opens with today
    /// already in it and saves perfectly well without the row being touched,
    /// and a prefilled optional row at the same weight as the amount overstates
    /// it.
    ///
    /// `.compact` shows the real date rather than a *Today* placeholder, so the
    /// capability is visible without occupying the screen: somebody who never
    /// needs it reads one extra line, and somebody adopting the app on day three
    /// of a trip can see that days one and two are enterable.
    private var dateRow: some View {
        qualifier {
            DatePicker(
                selection: $date,
                in: ...latestSelectableDate,
                displayedComponents: .date
            ) {
                Text("Date")
            }
            .datePickerStyle(.compact)
            // The label follows `.font`; the compact style's date pill does
            // not, so without this the row shrinks by half and reads as a
            // mistake rather than a step down the scale.
            .controlSize(.small)
        }
    }

    /// Today, except when an expense already carries a later date.
    ///
    /// An expense is something that happened, so the future is not offered: the
    /// error a bound catches is the fat-fingered year, which is invisible
    /// afterwards because it sorts to the top of the log and stays there. This
    /// is the tip cap's reasoning — a bound is for the typo, not the tipper.
    ///
    /// The `max` is not decoration. A stored date already beyond now — an older
    /// client, a skewed clock — would sit outside a bare `...Date()` range, and
    /// the picker resolves that by clamping, which is precisely the silent move
    /// of somebody else's data that `update` is written to prevent. Widening the
    /// range for a value that is already there costs nothing: it still cannot be
    /// *chosen*, only kept.
    private var latestSelectableDate: Date {
        max(seedDate, Date())
    }

    /// The one field this form cannot be saved without, drawn like it.
    ///
    /// A step up the type scale rather than a hand-picked size, so Larger Text
    /// keeps scaling it, and `.monospacedDigit()` so the figure stops shifting
    /// sideways as digits are typed. Every other row on this screen is either
    /// `body` or a `qualifier` below it; this is the only one above.
    private var amountRow: some View {
        HStack(spacing: 12) {
            // Hidden from VoiceOver because the field below carries the
            // same label — otherwise it is announced twice.
            Text(.amount)
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            TextField("0", text: $amountText)
                .focused($amountFocused)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold).monospacedDigit())
                // Without this the field's only label is its "0"
                // placeholder, which VoiceOver reads as "zero, text field".
                .accessibilityLabel("Amount")
                .accessibilityHint("In \(currencyCode)")

            currencyButton
        }
    }

    /// The currency, as a control on the amount rather than a row of its own.
    ///
    /// This was a `NavigationLink` in the Details section, which put the code
    /// that says what the figure *means* two rows away from the figure, and
    /// spent a whole row on it. Attached to the field it qualifies, it costs no
    /// height at all and reads the way a currency control reads everywhere
    /// else — the amount, then the unit, then a way to change the unit.
    ///
    /// Still the code and not a symbol, which is the older decision and still
    /// the right one: `$` and `kr` are each several currencies, and a form
    /// whose whole job is an unambiguous number should not label it ambiguously.
    ///
    /// `.borderless`, or the button takes the whole row and typing in the
    /// amount opens the picker — the same trap `nearbyButton` documents. The
    /// chevron is what makes it legible as a control rather than as the grey
    /// suffix it used to be, and the 44pt frame is what makes it hittable.
    private var currencyButton: some View {
        Button {
            showingCurrencyPicker = true
        } label: {
            HStack(spacing: 2) {
                Text(currencyCode)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Currency"))
        .accessibilityValue(Text(currencyCode))
    }

    /// The percentages offered before anyone has to type one.
    ///
    /// 12.5 earns its place: it is the standard discretionary service charge
    /// printed on a UK restaurant bill, and it is the one common figure that a
    /// round-numbers menu would force somebody to type by hand.
    private static let tipPresets: [Double] = [5, 10, 12.5, 15, 20]

    /// Formatted through `.percent` rather than by appending a literal `%`, so
    /// the sign lands where the reader's locale puts it and the decimal
    /// separator matches the amount field above.
    private static func percentText(_ percent: Double) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(0 ... 2)))
    }

    /// Tip, tax or service charge — one percentage added on top of the amount
    /// before it is split, so everybody shares it.
    ///
    /// A menu rather than a field, because on the commonest path this is one
    /// tap on a number somebody already knows, and a keyboard for "15" is three
    /// too many. Always visible, unlike `rateRow`: a tip applies to any group
    /// in any currency, and a control that only appears once it is relevant is
    /// one nobody discovers. It reads *None* until it is used, which is also
    /// what it must default to — a remembered 15% silently inflating the next
    /// bill is the one failure here nobody would catch.
    /// Where this expense happened, once a place has been picked.
    ///
    /// The row exists so the attachment is *visible at the moment it is made*,
    /// which is the condition the whole feature was made acceptable under. A
    /// place is the one thing on an expense that says where a person physically
    /// was, it goes into the shared zone with everything else, and it does not
    /// come back out — so it cannot be a fact the form acquired silently, and
    /// it has to be removable without deleting the expense.
    ///
    /// Absent entirely otherwise. An empty "Place —" row on every expense would
    /// advertise a feature most groups will never turn on.
    @ViewBuilder
    private var placeRow: some View {
        if let place = attached {
            qualifier {
                HStack {
                    // Two controls in one row, so each needs its own hit area:
                    // the name opens Maps, the cross detaches, and a row-wide
                    // tap target would make the destructive one the easy one to
                    // hit by accident.
                    Button {
                        NearbyPlaces.openInMaps(place)
                    } label: {
                        Label(place.name, systemImage: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    // Everything attached before `Dutch 9` has a name and no
                    // point, and a button that silently does nothing is worse
                    // than a label — so those rows stay labels.
                    .disabled(!place.isMappable)
                    .accessibilityLabel(
                        place.isMappable
                            ? Text("\(place.name), open in Maps")
                            : Text(place.name)
                    )

                    Spacer(minLength: 12)

                    Button {
                        attached = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove Place"))
                }
            }
        }
    }

    private var tipRow: some View {
        Menu {
            Button("None") { tip = .none }

            ForEach(Self.tipPresets, id: \.self) { percent in
                Button(Self.percentText(percent)) {
                    tip = TipRate(percent: percent).map(Tip.rate) ?? .none
                }
            }

            Divider()

            Button(.customTip) {
                customTipText = ""
                showingCustomTip = true
            }

            // Below the percentages and behind the same divider, exactly as
            // `Exact Amount…` sits below the presets in a split row's menu.
            // This is the mode switch, not a sixth preset: a tip reading
            // "5,00 zł" among four reading "15%" is the one item in here that
            // changes what the number means.
            Button(.tipAmountMenuItem) {
                flatTipText = ""
                showingFlatTip = true
            }

            // Offered only from a tip already expressed as a sum. Picking a
            // percentage does the same thing, but that is a discovery nobody
            // should have to make to undo something — the split rows make the
            // same offer for the same reason.
            if case .flat = tip {
                Divider()
                Button(.backToPercentage) { tip = .none }
            }
        } label: {
            // An `HStack`, not a `LabeledContent`, and that is not a style
            // preference. Inside a `Menu`, `LabeledContent` ignores a
            // `foregroundStyle` set on its *label* slot and paints it with the
            // accent colour anyway — so this row shipped with a blue **Tip**
            // against a grey **None**, which read as a button that was somehow
            // also switched off. The value slot honoured the same modifier
            // perfectly, which is what made it look like a styling mistake
            // rather than a control that overrides you.
            //
            // Laid out by hand it does as it is told, and it now matches
            // `amountRow` and `rateRow`, which were always plain stacks.
            //
            // The colour left on the value carries the meaning the share menu
            // below gives it: secondary while this sits at its default, tinted
            // once the user has actually set something. Tinted then means
            // "there is a tip on this expense", which is worth noticing on a
            // screen where the tip is folded into a total nothing itemises.
            qualifier {
                HStack {
                    Text("Tip")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Text(tip.isNone ? String(localized: "None") : tipFigure)
                        .foregroundStyle(
                            tip.isNone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint)
                        )
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityIdentifier("Tip")
    }

    /// The tip as the row and the footer both say it: a percentage, or money.
    ///
    /// Formatted in the currency being *entered*, which is what `Tip.flat`
    /// holds and what the person typed — not the group's, which the figure only
    /// becomes after the conversion the footer reports separately.
    private var tipFigure: String {
        switch tip {
        case .rate(let rate): Self.percentText(rate.percent)
        case .flat(let amount): amount.formatted(currencyCode: currencyCode)
        }
    }

    private func applyCustomTip() {
        guard
            let typed = DecimalInput.parse(customTipText),
            let rate = TipRate(percent: typed)
        else { return }
        tip = .rate(rate)
    }

    /// A blank or unreadable field clears the tip rather than storing something
    /// meaningless, which is also the documented way back out of a flat sum —
    /// the same contract `applyExactAmount` has one section below.
    private func applyFlatTip() {
        guard let typed = DecimalInput.parse(flatTipText), let flat = Tip.flat(typed) else {
            tip = .none
            return
        }
        tip = flat
    }

    /// Only meaningful when the money wasn't the group's own currency, so it
    /// stays out of the way entirely for the ordinary single-currency group.
    @ViewBuilder
    private var rateRow: some View {
        if isForeign {
            // A `qualifier` like the tip and the date, even though Save is
            // disabled without it. It is required only *because* a foreign
            // currency was chosen — on the row directly above, where the
            // currency control now lives — so it belongs to that choice rather
            // than standing beside the amount, and nothing here has to carry the
            // news that it is missing: the footer says "Enter the rate to
            // convert this to EUR" in words, which is louder than a font.
            qualifier {
                HStack {
                    Text("1 \(group.currency) =")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    Spacer(minLength: 12)

                    TextField("0", text: $rateText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .accessibilityLabel("Exchange rate")
                        .accessibilityHint("How many \(currencyCode) to one \(group.currency)")

                    Text(currencyCode)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// Rows rather than a `Picker`, so the payer carries the same circle the
    /// same person carries in the section directly below — and on the members
    /// list, and against every expense they paid for. A form that drew the same
    /// roster twice, once as colour and once as bare text, made the reader check
    /// whether they were even the same people.
    ///
    /// The cost is real and taken deliberately: the section is now as tall as
    /// the roster where it used to be one row. It sits at the top of a form
    /// nobody gets through without scrolling, and the tap it saves — open the
    /// menu, find the name, tap again — is one every expense pays.
    ///
    /// The old "Select…" row is gone with it. Nothing checked already says
    /// nothing is chosen, and Save stays disabled until something is.
    private func paidBySection(_ members: [Person], _ avatars: RosterAvatars) -> some View {
        let contributions = contributionPreview

        return Section {
            if members.isEmpty {
                Text(.addMembersFirst)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.objectID) { member in
                    PayerRow(
                        name: member.name ?? "?",
                        avatar: avatars[member],
                        isSelected: selectedPayers.contains(member),
                        // Nothing at all until a second payer joins, so the
                        // ordinary expense — one person, whole amount — is the
                        // row it has always been. The control appearing *is*
                        // how the form says the rules just changed.
                        contribution: severalPayers && selectedPayers.count > 1
                            ? (payerAmounts[member] ?? contributions[member])
                            : nil,
                        isContributionTyped: payerAmounts[member] != nil,
                        currencyCode: currencyCode,
                        onTap: { togglePayer(member) },
                        onContribution: { beginContribution(for: member) }
                    )
                }

                // Absent entirely on an edit rather than disabled: an edit
                // rewrites one record, so there is no state this could put the
                // form into, and a permanently greyed switch invites the
                // question of what would turn it on.
                if allowsSeveralPayers {
                    Toggle("Several people paid", isOn: severalPayersBinding(members))
                        // Nothing to divide between one person.
                        .disabled(members.count < 2)
                }
            }
        } header: {
            Text("Paid By")
        } footer: {
            if let payerFooter {
                Text(payerFooter)
                    .motionContentTransition(.numericText())
            }
        }
    }

    private func splitAmongSection(
        _ slices: [Person: Money],
        _ members: [Person],
        _ avatars: RosterAvatars
    ) -> some View {
        Section {
            if members.isEmpty {
                Text(.addMembersFirst)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.objectID) { member in
                    MemberSplitRow(
                        name: member.name ?? "?",
                        avatar: avatars[member],
                        isSelected: selectedParticipants.contains(member),
                        share: splitsEvenly ? nil : share(for: member),
                        currencyCode: currencyCode,
                        slice: slices[member].map { $0.formatted(in: group) },
                        onTap: { toggle(member) },
                        onShareChange: {
                            shares[member] = $0
                            // Picking a percentage is how you leave exact mode,
                            // so the figure goes with it — a row cannot be both
                            // and a leftover amount would keep winning.
                            exactAmounts[member] = nil
                        },
                        onCustomShare: { beginCustomShare(for: member) },
                        onExactShare: { beginExactAmount(for: member) },
                        onClearExact: { clearExactAmount(for: member) }
                    )
                }

                // Disabled below two people because there is nothing to weight
                // — a lone sharer takes the whole amount at any percentage.
                Toggle("Uneven split", isOn: sharesBinding)
                    .disabled(selectedParticipants.count < 2)
            }
        } header: {
            HStack {
                Text(.splitAmong)
                Spacer()
                if !members.isEmpty {
                    // Splitting evenly across everyone is the common case, and
                    // it used to cost one tap per member.
                    let everyone = allSelected(in: members)
                    Button(everyone ? .selectNone : .selectEveryone) {
                        withAnimation(.snappy) {
                            selectedParticipants = everyone ? [] : Set(members)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)  // section headers uppercase; the button shouldn't
                }
            }
        } footer: {
            if splitsEvenly {
                // The payer is not added implicitly — leaving them out is
                // how you record paying purely on someone else's behalf.
                Text(.excludePayerSplitExplanation)
            } else if let remainderSummary {
                VStack(alignment: .leading, spacing: 4) {
                    // Leads, because it is the line that changes as you work
                    // and the one Save depends on.
                    Text(remainderSummary)
                        .motionContentTransition(.numericText())

                    // Only when the two registers are actually on screen
                    // together. A typed figure directly above a percentage
                    // invites reading both as money — the first person to hit
                    // this read `10%` beside `50,00 zł` on a 250,00 bill and
                    // expected 20,00 rather than the 18,18 a tenth of a share
                    // comes to. Both numbers were on screen and correct; what
                    // was missing was which register the percentage was in.
                    //
                    // Withheld when every remaining row is a plain full share,
                    // which is the ordinary "somebody pays their own, the rest
                    // of us split what's left" case. The percentages are all
                    // equal there, so nothing about them needs explaining and
                    // a second line would be permanent furniture.
                    if mixesExactAndPartialShares {
                        Text(.shareOfRemainderExplanation)
                    }
                }
            } else {
                // Says outright that the percentages don't add up to 100,
                // because they don't — six people with one 51%-off fare comes
                // to 549%. Without this the first reaction to that is that the
                // app is broken, so the sentence points at the amounts, which
                // *do* add up, as the thing to trust.
                Text(.percentageSplitExplanation)
            }
        }
    }

    // MARK: - Selection

    private func allSelected(in members: [Person]) -> Bool {
        !members.isEmpty && selectedParticipants.count == members.count
    }

    private func toggle(_ member: Person) {
        withAnimation(.snappy) {
            if selectedParticipants.contains(member) {
                selectedParticipants.remove(member)
                // Dropped rather than kept: a weight belonging to someone no
                // longer in the split would reappear from nowhere if they were
                // added back later. Both kinds, for the same reason — an exact
                // figure left behind would also change what everyone else pays,
                // by shrinking the remainder they divide.
                shares[member] = nil
                exactAmounts[member] = nil
            } else {
                selectedParticipants.insert(member)
            }
        }
    }

    private func share(for member: Person) -> RowShare? {
        guard selectedParticipants.contains(member) else { return nil }
        if let exact = exactAmounts[member] { return .exact(exact) }
        return .percent(shares[member] ?? Share.full)
    }

    // MARK: - Typing in a share

    private func beginCustomShare(for member: Person) {
        // The row's percentage rather than what it currently displays: a row
        // showing an exact figure opens this on the percentage it would go back
        // to, not on a money amount reinterpreted as one.
        customText = String(shares[member] ?? Share.full)
        customTarget = member
    }

    private var customBinding: Binding<Bool> {
        Binding(
            get: { customTarget != nil },
            set: { if !$0 { customTarget = nil } }
        )
    }

    /// Clamped rather than rejected. A stray extra digit is far likelier than
    /// a genuine 1000% share, and refusing the whole entry would throw away a
    /// number the user has just typed.
    private func applyCustomShare() {
        defer { customTarget = nil }

        guard
            let member = customTarget,
            let typed = Int(customText.trimmingCharacters(in: .whitespaces))
        else { return }

        withAnimation(.snappy) {
            shares[member] = min(max(typed, Share.range.lowerBound), Share.range.upperBound)
            exactAmounts[member] = nil
        }
    }

    // MARK: - Typing in an exact amount

    private func beginExactAmount(for member: Person) {
        exactText = exactAmounts[member].map { DecimalInput.text($0.amount) } ?? ""
        exactTarget = member
    }

    private var exactBinding: Binding<Bool> {
        Binding(
            get: { exactTarget != nil },
            set: { if !$0 { exactTarget = nil } }
        )
    }

    /// An unreadable or negative figure puts the row back on a percentage
    /// rather than storing something meaningless. Clearing the field is the
    /// documented way out of exact mode, which is why an empty string is not
    /// an error here.
    private func applyExactAmount() {
        defer { exactTarget = nil }
        guard let member = exactTarget else { return }

        withAnimation(.snappy) {
            guard let typed = DecimalInput.parse(exactText), typed >= 0 else {
                exactAmounts[member] = nil
                return
            }
            exactAmounts[member] = Money(amount: typed)
        }
    }

    /// Back to a percentage, from the row's own menu.
    private func clearExactAmount(for member: Person) {
        withAnimation(.snappy) { exactAmounts[member] = nil }
    }

    /// Turning shares off discards the weighting rather than hiding it. A
    /// weighting that is invisible but still applied is the worst of both: the
    /// form would say "even" while the balances disagreed.
    private var sharesBinding: Binding<Bool> {
        Binding(
            get: { !splitsEvenly },
            set: { wantsShares in
                withAnimation(.snappy) {
                    splitsEvenly = !wantsShares
                    if !wantsShares {
                        shares = [:]
                        exactAmounts = [:]
                    }
                }
            }
        )
    }

    /// What each member will actually be charged, for the rows to show.
    ///
    /// Routed through `SettlementCalculator.slices` rather than divided here,
    /// so the preview and the balance it becomes are the same arithmetic down
    /// to the cent — including which member the leftover lands on.
    private var slicePreview: [Person: Money] {
        guard !splitsEvenly, let amount = finalAmount else { return [:] }

        // Empty while the split doesn't add up, so the rows go quiet rather
        // than showing per-person figures derived from a total nobody agreed
        // to. The footer is what explains the state; a row quietly showing a
        // plausible number would contradict it.
        let weights = weightsByID
        guard !weights.isEmpty else { return [:] }

        let byID = Dictionary(
            SettlementCalculator.slices(of: amount, among: weights)
                .map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        return selectedParticipants.reduce(into: [:]) { result, member in
            if let id = member.id, let slice = byID[id] {
                result[member] = slice
            }
        }
    }

    /// The figure the split is laid against: the amount exactly as typed,
    /// before the tip and before any conversion.
    ///
    /// Not `finalAmount`, deliberately. The exact rows are lines off a receipt,
    /// and the receipt is in the currency being typed in and does not include
    /// the tip that gets added afterwards. Because the weighting that comes out
    /// is *relative*, both then apply themselves proportionally — everyone pays
    /// their own item, converted, plus their share of the tip.
    private var splitBasis: Money? { parsedAmount.map(Money.init(amount:)) }

    /// How the split currently resolves, or `nil` when it is even or there is
    /// no figure to divide yet.
    private var splitPlan: ExactSplit.Plan? {
        guard !splitsEvenly, let basis = splitBasis else { return nil }

        var fixed: [UUID: Money] = [:]
        var sharing: [UUID: Int] = [:]

        for member in selectedParticipants {
            guard let id = member.id else { continue }
            if let exact = exactAmounts[member] {
                fixed[id] = exact
            } else {
                sharing[id] = shares[member] ?? Share.full
            }
        }

        return ExactSplit.plan(total: basis, fixed: fixed, sharing: sharing)
    }

    /// Whether more than one payer can be chosen at all.
    ///
    /// Everywhere, edits included. This was add-only at first, on the reasoning
    /// that an edit rewrites one record and has nowhere to put a second payer
    /// without silently creating a row. Two things answered that. The row is
    /// not silent — `payerFooter` names it before Save. And it can be dated
    /// correctly, which is only true because the form carries a date field:
    /// before it did, a payer added to last Tuesday's taxi would have landed in
    /// today's bucket.
    ///
    /// What it replaces is worse than a created row. Remembering afterwards
    /// that somebody else chipped in used to mean deleting the expense and
    /// entering two — on a shared group, exactly the delete-and-re-add churn
    /// that editing exists to prevent.
    private var allowsSeveralPayers: Bool { true }

    /// The figure the contributions are laid against: the amount with the tip
    /// on it, still in the currency being typed.
    ///
    /// Tipped, where `splitBasis` is not. What a payer handed over included the
    /// tip; what a sharer's receipt line says did not.
    private var payerBasis: Money? { tippedAmount.map(Money.init(amount:)) }

    /// How the contributions currently resolve, or `nil` when only one person
    /// is paying and there is nothing to divide.
    private var payerPlan: ExactSplit.Plan? {
        guard selectedPayers.count > 1, let basis = payerBasis else { return nil }

        var fixed: [UUID: Money] = [:]
        var sharing: [UUID: Int] = [:]

        for payer in selectedPayers {
            guard let id = payer.id else { continue }
            if let typed = payerAmounts[payer] {
                fixed[id] = typed
            } else {
                // A flat weight, not a percentage. Payers have no shares to be
                // a proportion of — somebody who hasn't said what they put in
                // simply covers an equal part of what's left.
                sharing[id] = 1
            }
        }

        return ExactSplit.plan(total: basis, fixed: fixed, sharing: sharing)
    }

    /// The contributions as weights, which is all `addExpenses` needs: they are
    /// relative, so the tip and the conversion both carry through.
    private var contributionWeights: [Person: Int] {
        guard selectedPayers.count > 1 else {
            return selectedPayers.reduce(into: [:]) { $0[$1] = 1 }
        }
        guard let plan = payerPlan, plan.isSatisfiable else { return [:] }

        return selectedPayers.reduce(into: [:]) { result, payer in
            if let id = payer.id, let weight = plan.weights[id] {
                result[payer] = weight
            }
        }
    }

    /// What each payer will be recorded as having put in, for the rows.
    private var contributionPreview: [Person: Money] {
        guard
            selectedPayers.count > 1,
            let basis = payerBasis,
            let plan = payerPlan, plan.isSatisfiable
        else { return [:] }

        let byID = Dictionary(
            SettlementCalculator.slices(of: basis, among: plan.weights)
                .map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        return selectedPayers.reduce(into: [:]) { result, payer in
            if let id = payer.id, let slice = byID[id] {
                result[payer] = slice
            }
        }
    }

    /// Where the contributions stand against the payment, in words.
    private var payerFooter: String? {
        guard selectedPayers.count > 1 else { return nil }
        guard let plan = payerPlan else {
            return String(
                localized: "Each of them will get an expense of their own.",
                comment: "Shown when several payers are selected but no amount has been entered yet."
            )
        }

        let figure = plan.remainder.magnitude.formatted(currencyCode: currencyCode)

        if plan.overshoots {
            return String(
                localized: "That is \(figure) more than the amount above.",
                comment: "Shown when the contributions typed for several payers come to more than the expense. The placeholder is a formatted money amount."
            )
        }

        // The round trip is asymmetric — one thing goes in and several come
        // back out — so the form says so before Save rather than leaving it to
        // be discovered in the log.
        //
        // Worded differently on an edit, where it is not a description of how
        // the save works but a warning: rows are about to appear and this one
        // is about to get smaller.
        //
        // Deliberately without a count of the new rows. It would read better in
        // English and would need plural variations in both languages to not
        // read badly in Polish, which has four categories to English's two —
        // a lot of catalog for a number that is almost always one.
        guard isEditing else {
            return String(
                localized: "Saved as one expense per payer.",
                comment: "Shown when several people paid, explaining that the app records a separate expense for each of them."
            )
        }

        return String(
            localized: "The other payers will be saved as separate expenses on the same date, and this one reduced to its payer's part.",
            comment: "Shown when editing an expense and adding further payers, warning that saving will create new expenses and shrink this one."
        )
    }

    // MARK: - Typing in a contribution

    private func beginContribution(for payer: Person) {
        payerText = payerAmounts[payer].map { DecimalInput.text($0.amount) } ?? ""
        payerTarget = payer
    }

    private var payerAmountBinding: Binding<Bool> {
        Binding(
            get: { payerTarget != nil },
            set: { if !$0 { payerTarget = nil } }
        )
    }

    /// Clearing the field hands the payer back to an equal part of whatever the
    /// typed contributions leave, which is the way out of having said a figure.
    private func applyContribution() {
        defer { payerTarget = nil }
        guard let payer = payerTarget else { return }

        withAnimation(.snappy) {
            guard let typed = DecimalInput.parse(payerText), typed >= 0 else {
                payerAmounts[payer] = nil
                return
            }
            payerAmounts[payer] = Money(amount: typed)
        }
    }

    private func togglePayer(_ member: Person) {
        withAnimation(.snappy) {
            // One tap, and it means what it has always meant. Everything below
            // is reachable only once the toggle has said this expense is the
            // unusual kind.
            guard severalPayers, allowsSeveralPayers else {
                selectedPayers = [member]
                payerAmounts = [:]
                return
            }

            if selectedPayers.contains(member) {
                // Never down to nobody: the form cannot be saved without a
                // payer, and a tap that greys out Save with no other cue reads
                // as the row having broken.
                guard selectedPayers.count > 1 else { return }
                selectedPayers.remove(member)
            } else {
                selectedPayers.insert(member)
            }
        }
    }

    /// Turning several payers off keeps the topmost selected row, which is the
    /// one the eye is already on, and discards the contributions with it —
    /// `sharesBinding` drops a weighting the same way and for the same reason.
    /// A figure still being applied while the form says one person paid is the
    /// worst of both.
    private func severalPayersBinding(_ members: [Person]) -> Binding<Bool> {
        Binding(
            get: { severalPayers },
            set: { wantsSeveral in
                withAnimation(.snappy) {
                    severalPayers = wantsSeveral
                    guard !wantsSeveral else { return }
                    payerAmounts = [:]
                    if let first = members.first(where: selectedPayers.contains) {
                        selectedPayers = [first]
                    }
                }
            }
        )
    }

    /// Whether a typed figure and a partial share are on screen at once.
    ///
    /// The condition for saying what a percentage is measured against. Not
    /// simply "are there exact amounts": a split where everyone else is on a
    /// plain 100% has nothing ambiguous in it, and the explanation would be
    /// showing permanently for the commonest shape this feature has.
    private var mixesExactAndPartialShares: Bool {
        guard !exactAmounts.isEmpty else { return false }

        return selectedParticipants.contains { member in
            exactAmounts[member] == nil && (shares[member] ?? Share.full) != Share.full
        }
    }

    /// The number of rows still dividing whatever the exact ones leave behind.
    private var sharingRowCount: Int {
        selectedParticipants.filter { exactAmounts[$0] == nil }.count
    }

    /// The weighting as the store and the calculator want it. Empty while the
    /// split is even, which is what leaves the stored expense unweighted — and
    /// empty when it doesn't add up, which `isValid` refuses to save anyway.
    ///
    /// With no exact rows this is the percentages, untouched: `ExactSplit`
    /// passes a weighting with nothing fixed straight through, so every expense
    /// already stored as a percentage split is written back exactly as it was.
    private var weightsByID: [UUID: Int] {
        guard let plan = splitPlan, plan.isSatisfiable else { return [:] }
        return plan.weights
    }

    /// The members whose figure was typed rather than derived, for the markers
    /// that let an edit reopen showing the same thing.
    private var exactIDs: Set<UUID> {
        guard splitPlan?.isSatisfiable == true else { return [] }
        return Set(exactAmounts.keys.compactMap(\.id))
    }

    /// Where the money stands against the total, in words, whenever any of it
    /// has been entered by hand.
    ///
    /// The roadmap's condition for this feature existing at all: fixed rows are
    /// being typed against a total, and without a running figure the user is
    /// doing that arithmetic in their head — which is the thing the app is for.
    /// `nil` on an ordinary percentage split, where there is no remainder to
    /// track and the standing explanation is the more useful sentence.
    private var remainderSummary: String? {
        guard !splitsEvenly, !exactAmounts.isEmpty, let plan = splitPlan else { return nil }

        let figure = plan.remainder.magnitude.formatted(currencyCode: currencyCode)

        if plan.overshoots {
            return String(
                localized: "That is \(figure) more than the amount above.",
                comment: "Shown when the exact amounts typed against a split come to more than the expense. The placeholder is a formatted money amount."
            )
        }

        guard sharingRowCount > 0 else {
            return plan.remainder.isZero
                ? String(
                    localized: "The amounts add up to the total.",
                    comment: "Shown when every member's exact amount has been typed and they sum to the expense exactly."
                )
                : String(
                    localized: "\(figure) of the total is still unaccounted for.",
                    comment: "Shown when exact amounts fall short of the expense and no member is left to absorb the difference. The placeholder is a formatted money amount."
                )
        }

        return plan.remainder.isZero
            ? String(
                localized: "The amounts use up the total, so everybody else pays nothing.",
                comment: "Shown when the exact amounts already come to the whole expense while other members are still in the split."
            )
            : String(
                localized: "\(figure) left for the others to split.",
                comment: "Shown while some members have an exact amount and the rest divide what remains. The placeholder is a formatted money amount."
            )
    }

    // MARK: - Nearby

    /// Takes the place the user picked: always as the attachment, and as the
    /// title only when there isn't one yet.
    ///
    /// The first version overwrote the title outright, on the reasoning that a
    /// tap plus a row chosen is two explicit answers to "what is this called".
    /// The reasoning was fine and the behaviour was wrong: the case it loses is
    /// somebody who typed *Anna's birthday*, then attached the café — and had
    /// their sentence replaced by a shop sign. Typing is the more specific
    /// answer of the two, and it is also the one that took effort.
    ///
    /// So an empty title takes the name and a written one is left alone. The
    /// place attaches either way, which is what makes this safe: nothing is
    /// lost by not filling the title, because the attachment is the thing being
    /// recorded and the row below shows it.
    private func adopt(_ place: NearbyPlaces.Place) {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            title = place.name
        }
        attached = ExpensePlace(place)
        adoptCurrency(of: place)
    }

    /// Switches the expense into the local currency, from the country of the
    /// place that was just chosen.
    ///
    /// The country comes off the picked `MKMapItem` rather than from a
    /// reverse-geocode of the device: it is already in hand, it costs no second
    /// network call, and it is the country of a place the user named out loud
    /// rather than an inference about where they are.
    ///
    /// Four guards, and each one is a way this could be wrong rather than
    /// merely unhelpful:
    ///
    /// - **The setting.** Off by default. Somebody can reasonably want the
    ///   café's name without wanting the form to change the figure's meaning.
    /// - **Never while editing.** Reopening an expense saved in Budapest, from
    ///   a table in Kraków, must not rewrite the currency it was saved in — the
    ///   amount underneath it would keep its digits and quietly change value.
    /// - **A country with no currency answers `nil`**, and `nil` means leave it
    ///   alone. Never `Locale.current.region`, which is the device's *setting*
    ///   rather than where it is, and so is wrong for exactly the traveller
    ///   this feature exists for.
    /// - **No change is not a change.** Assigning the same code would still fire
    ///   `onChange` below and re-derive a rate the user may have just typed
    ///   over.
    private func adoptCurrency(of place: NearbyPlaces.Place) {
        guard
            !isEditing,
            ExpenseDefaults.prefillsCurrencyFromLocation,
            let region = place.regionCode,
            let local = RegionCurrency.code(for: region),
            local != currencyCode
        else { return }

        // Assigns the code and stops. The rate belongs to `onChange(of:)`
        // above, which looks up whatever this group last used *for this
        // currency* and leaves the field empty when there is nothing — so an
        // unseen currency disables Save until a rate is entered, rather than
        // converting at the last country's. Setting `rateText` here as well
        // would be the bug that entry warns about, written a second time.
        currencyCode = local
    }

    // MARK: - Currency

    private var isForeign: Bool { currencyCode != group.currency }

    /// The codes actually in play in this group: its own first, then whatever
    /// is selected, then the foreign currencies it has already spent in.
    ///
    /// These get a section of their own above the full list rather than merely
    /// being sorted to the top of it — a run of familiar codes with no heading
    /// over it reads as the alphabet having gone wrong.
    ///
    /// The selection is included explicitly so a code outside
    /// `commonISOCurrencyCodes`, which is not the whole ISO register, still has
    /// a row of its own to show its tick on.
    private var inUseCurrencies: [String] {
        var seen = Set<String>()
        return ([group.currency, currencyCode] + recentCurrencies)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Validation

    private var parsedAmount: Double? { DecimalInput.parse(amountText) }

    /// The entered figure with the tip on top, which is what everything below
    /// converts and stores.
    ///
    /// Applied here, in the currency the money was actually handed over in and
    /// before any conversion, for the reason spelled out in `Tip.applied`: the
    /// amount is rounded to minor units exactly once, and tipping after that
    /// would round twice and let a split miss its own total by a cent. It also
    /// means a tipped foreign bill records what was really paid — 1 650 HUF,
    /// not 1 500 with a euro adjustment bolted on.
    ///
    /// True of a flat sum as much as of a percentage, and that is why the flat
    /// case holds a figure in the *entered* currency: 150 HUF added to 1 500
    /// HUF, converted once. A tip held in the group's currency would have to be
    /// converted back to be added, which is a second rounding wearing a
    /// disguise.
    private var tippedAmount: Double? {
        parsedAmount.map(tip.applied(to:))
    }

    /// The foreign-currency figure being entered, once it is complete enough to
    /// convert. `nil` while the rate is missing or unusable — `ForeignAmount`
    /// rejects a zero rate rather than dividing by it.
    private var foreignAmount: ForeignAmount? {
        guard isForeign, let amount = tippedAmount, let rate = DecimalInput.parse(rateText) else {
            return nil
        }
        return ForeignAmount(amount: amount, currencyCode: currencyCode, rate: rate)
    }

    /// What will actually be stored: always in the group's currency, converted
    /// exactly once, here.
    private var finalAmount: Money? {
        if isForeign { return foreignAmount?.converted }
        return tippedAmount.map(Money.init(amount:))
    }

    /// Echoes back exactly what will be stored, so a mis-parsed separator, a
    /// rate entered upside down or a tip nobody meant to leave on is catchable
    /// before saving rather than after.
    ///
    /// Every clause goes through `String(localized:)`. This property returns a
    /// `String`, and `Text(_: String)` is the *non-localizing* initializer — so
    /// an ordinary interpolated literal here reaches a Polish phone in English
    /// with no warning anywhere, which is what happened to this whole footer
    /// until 2026-08-28. Assembled from parts rather than one long format
    /// string so a translator gets three short sentences instead of one with
    /// four placeholders in it, and so the tip clause can simply be absent.
    private var savesAsSummary: String? {
        guard let amount = finalAmount else {
            // Otherwise a foreign expense with no rate yet just leaves Save
            // greyed out with nothing on screen saying which field is missing.
            if isForeign, parsedAmount != nil {
                return String(
                    localized: "Enter the rate to convert this to \(group.currency).",
                    comment: "Shown when a foreign amount has been typed but no exchange rate yet. The placeholder is the group's currency code."
                )
            }
            return nil
        }

        var parts = [
            String(
                localized: "Saves as \(amount.formatted(in: group))",
                comment: "The amount that will actually be stored, in the group's currency."
            )
        ]

        if let foreign = foreignAmount {
            let rate = foreign.rate.formatted(.number.precision(.fractionLength(0 ... 6)))
            parts.append(
                String(
                    localized: "\(foreign.formatted()) at \(rate)",
                    comment: "The amount as it was paid abroad and the rate it was converted at, e.g. '198,50 zł at 4.4111'."
                )
            )
        }

        if !tip.isNone {
            // One sentence for both kinds, with either a percentage or a money
            // figure in it. The clause reads the same either way — "15% tip
            // included", "5,00 zł tip included" — so splitting it in two would
            // hand a translator the same sentence twice.
            parts.append(
                String(
                    localized: "\(tipFigure) tip included",
                    comment: "Notes that the stored amount already has a tip in it. The placeholder is either a formatted percentage, e.g. '15%', or a formatted money amount, e.g. '5,00 zł' — the sentence is the same for both."
                )
            )
        }

        return parts.joined(separator: " · ")
    }

    /// A title is deliberately not required.
    ///
    /// What an expense has to have is a figure, somebody who paid it and
    /// somebody it is split between — those three are what a balance is made
    /// of, and a title is a label on top of them. Requiring one meant standing
    /// at a bar typing "Beer" before the app would accept the number, and the
    /// list already reads fine without it: `ExpenseRow` leads an untitled row
    /// with the payer instead.
    private var isValid: Bool {
        finalAmount != nil
            && !selectedPayers.isEmpty
            // Contributions have to reconstruct the payment, on the same
            // reasoning as the split above.
            && (payerPlan.map(\.isSatisfiable) ?? true)
            && !selectedParticipants.isEmpty
            // A split that doesn't reconstruct the whole is refused rather than
            // rounded into shape. `PartialPaymentSheet` already sets the
            // precedent — an overpayment is blocked with the figure named, not
            // silently clamped — and the footer above says by how much.
            && (splitPlan.map(\.isSatisfiable) ?? true)
    }

    // MARK: - Save

    private func save() {
        guard let amount = finalAmount else { return }
        // The single payer, for the two paths that can only mean one: an edit
        // rewrites one record, and `ExpenseDefaults` remembers one person.
        let payer = selectedPayers.count == 1 ? selectedPayers.first : nil
        let foreign = foreignAmount
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let weights = weightsByID
        let exact = exactIDs

        do {
            if let editing {
                try store.update(
                    editing,
                    title: trimmed,
                    amount: amount,
                    // A lone payer is handed straight back to the ordinary
                    // in-place rewrite, so the commonest edit there is takes
                    // exactly the path it always did.
                    contributions: contributionWeights,
                    splitAmong: selectedParticipants,
                    category: category,
                    at: attached,
                    // Only when it actually moved. An untouched picker passes
                    // `nil`, which leaves the stored value exactly as it was —
                    // including leaving a dateless record dateless, rather than
                    // stamping today on it for fixing a typo in the title.
                    on: date == seedDate ? nil : date,
                    paidIn: foreign,
                    shares: weights,
                    exactShares: exact
                )
            } else {
                // One record per payer, and for the ordinary single payer that
                // is one record written exactly as it always was — `addExpenses`
                // hands a lone contributor straight back to `addExpense`.
                try store.addExpenses(
                    title: trimmed,
                    amount: amount,
                    contributions: contributionWeights,
                    splitAmong: selectedParticipants,
                    in: group,
                    category: category,
                    at: attached,
                    on: date,
                    paidIn: foreign,
                    shares: weights,
                    exactShares: exact
                )
                // Only when adding. An edit corrects something recorded
                // earlier — often much earlier — and letting it rewrite "the
                // last currency used" would prefill the next expense from a
                // receipt two countries ago.
                //
                // And only for a lone payer: "who usually pays" cannot be two
                // people, and picking one of them to remember would prefill the
                // next expense with a name the user never chose.
                remember(payer: payer, foreign: foreign)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remember(payer: Person?, foreign: ForeignAmount?) {
        payer.map { ExpenseDefaults.rememberPayer($0, in: group) }
        if let foreign {
            ExpenseDefaults.remember(foreign, in: group)
            // Only the foreign ones. The group's own currency is pinned to the
            // top of the picker whatever happens, so recording it here would
            // spend one of four slots on the one code that cannot go missing.
            ExpenseDefaults.rememberUsed(foreign.currencyCode, in: group)
        } else {
            ExpenseDefaults.rememberHomeCurrency(in: group)
        }
    }
}

// MARK: - Payer Row

/// One candidate payer.
///
/// The same circle and the same 12pt gutter as `MemberSplitRow` below, because
/// the two sections list the same people — but a bare checkmark where that one
/// has a filled circle. They are different questions: the split takes any number
/// of people and shows an empty circle per row to say so, where exactly one
/// person paid. Reusing the multi-select mark here would have promised a choice
/// this section doesn't offer.
private struct PayerRow: View {
    let name: String
    let avatar: PersonAvatar
    let isSelected: Bool
    /// What this person put in, or `nil` while only one person is paying and
    /// the answer is "all of it".
    let contribution: Money?
    /// Whether that figure was typed or worked out from what the others left.
    let isContributionTyped: Bool
    let currencyCode: String
    let onTap: () -> Void
    let onContribution: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Dimmed rather than hidden for a row that isn't paying,
                    // for the same reason as the split rows: a circle that
                    // vanishes makes the list jump as the selection moves.
                    PersonIcon(avatar)
                        .opacity(isSelected ? 1 : 0.4)

                    Text(name)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 12)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected, let contribution {
                // Tinted only once somebody has actually said a figure. A
                // derived one is the app's arithmetic rather than the user's
                // decision, and colouring the two alike would make an equal
                // share look like a choice that had been made.
                Button(action: onContribution) {
                    Text(contribution.formatted(currencyCode: currencyCode))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(
                            isContributionTyped
                                ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                        )
                        .motionContentTransition(.numericText())
                        .padding(.vertical, 12)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Contribution from \(name)")
                .accessibilityValue(contribution.formatted(currencyCode: currencyCode))
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Marks this person as one of those who paid")
        // The same person is now a row in both sections of this form, so a UI
        // test reaching for them by name has two candidates and takes whichever
        // the tree walks into first. An identifier is invisible to VoiceOver —
        // the label above is what gets spoken — and says which row is meant.
        .accessibilityIdentifier("payer-\(name)")
    }
}

// MARK: - Member Row

/// Extracted so the `Form` body stays small enough for the type checker.
private struct MemberSplitRow: View {
    let name: String
    let avatar: PersonAvatar
    let isSelected: Bool
    /// How this member's share is being expressed, or `nil` when the split is
    /// even and no control should appear at all.
    let share: RowShare?
    /// The currency an exact figure was typed in — the one the amount field is
    /// using, which is not necessarily the group's.
    let currencyCode: String
    /// What this member will be charged, once there is an amount to divide.
    let slice: String?
    let onTap: () -> Void
    let onShareChange: (Int) -> Void
    let onCustomShare: () -> Void
    let onExactShare: () -> Void
    let onClearExact: () -> Void

    /// What the control reads. A percentage keeps its sign; an exact figure is
    /// formatted as money, so the two can never be misread for one another at
    /// a glance — which is the entire reason they are separate modes.
    private func label(for share: RowShare) -> String {
        switch share {
        case .percent(let percent): percent.formatted(.percent)
        case .exact(let amount): amount.formatted(currencyCode: currencyCode)
        }
    }

    /// Quiet only for a plain full share, which is the default and says
    /// nothing. Anything the user actually chose — a percentage or a figure —
    /// is tinted, because it is the reason this row differs from the others.
    private func isDefault(_ share: RowShare) -> Bool {
        share == .percent(Share.full)
    }

    /// Spelled out rather than read as a bare number, which on its own says
    /// neither what it is nor which of the two kinds it is.
    private func accessibleShare(_ share: RowShare) -> String {
        switch share {
        case .percent(let percent):
            String(
                localized: "\(percent) percent of a full share",
                comment: "VoiceOver value for a member's weighted share. The placeholder is a whole-number percentage."
            )
        case .exact(let amount):
            String(
                localized: "Exactly \(amount.formatted(currencyCode: currencyCode))",
                comment: "VoiceOver value for a member whose share was typed as a cash figure. The placeholder is a formatted money amount."
            )
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // A `Button`, not a tap gesture on a shape. To VoiceOver the old
            // row was static text: no button trait, no selected state, nothing
            // to activate. The empty circle matters too — an unselected member
            // used to show nothing at all, so there was no cue the row was
            // tappable.
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Dimmed rather than hidden when the member is out of the
                    // split: the row still has to be identifiable at a glance,
                    // and a circle that vanishes makes the list jump as people
                    // are toggled in and out.
                    PersonIcon(avatar)
                        .opacity(isSelected ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .foregroundStyle(.primary)

                        // Only with an uneven split, where "2×" on its own
                        // doesn't tell anyone what they are actually paying.
                        if isSelected, let slice {
                            Text(slice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .motionContentTransition(.numericText())
                        }
                    }

                    Spacer(minLength: 12)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .imageScale(.large)
                        .motionContentTransition(.symbolEffect(.replace))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            // See `PayerRow`: the same name appears in both sections now.
            .accessibilityIdentifier("sharer-\(name)")

            if isSelected, let share {
                // A menu, not a stepper or a slider. The two cases this exists
                // for are a couple sharing a room (50%) and a discounted fare
                // (49%): the first is one tap here, and the second is a number
                // no thumb can land on with a slider and no one wants to reach
                // by tapping a stepper 51 times.
                Menu {
                    ForEach(Share.presets, id: \.self) { preset in
                        Button {
                            onShareChange(preset)
                        } label: {
                            if share == .percent(preset) {
                                Label(preset.formatted(.percent), systemImage: "checkmark")
                            } else {
                                Text(preset.formatted(.percent))
                            }
                        }
                    }
                    Divider()
                    Button("Other…", action: onCustomShare)
                    // Below the percentages and behind its own divider: this is
                    // the mode switch, not a fifth preset, and a row reading
                    // "23,50" alongside four reading "50%" is the one thing in
                    // this menu that changes what the numbers mean.
                    Button(.exactAmountMenuItem, action: onExactShare)

                    // Offered only from a row already in exact mode. Tapping a
                    // percentage does the same thing, but that is a discovery
                    // nobody should have to make to undo something.
                    if case .exact = share {
                        Divider()
                        Button(.backToPercentage, action: onClearExact)
                    }
                } label: {
                    Text(label(for: share))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(isDefault(share) ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                        .motionContentTransition(.numericText())
                        // Padding, not a frame: the tappable area has to clear
                        // 44pt without the text jumping around as it goes from
                        // "50%" to "100%".
                        .padding(.vertical, 12)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Share for \(name)")
                .accessibilityValue(accessibleShare(share))
            }
        }
    }
}

#Preview("Add") {
    ExpenseFormView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
