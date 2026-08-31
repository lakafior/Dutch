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
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []
    /// What each member pays as a percentage of a full share, used only while
    /// `splitsEvenly` is off. A member with no entry pays a full 100%.
    ///
    /// Relative, not a division of the bill: these do not add up to 100. Six
    /// people, one of them on a 51%-off fare, is five entries of `100` and one
    /// of `49` — which sums to 549% and is exactly right. Nothing shows the
    /// user that total; the rows show złoty amounts, and those do add up.
    @State private var shares: [Person: Int] = [:]
    @State private var splitsEvenly: Bool
    /// The member whose share is being typed in by hand, and the text of it.
    @State private var customTarget: Person?
    @State private var customText = ""
    /// Tip, tax or service charge, as a percentage of the entered amount.
    ///
    /// A plain `Double` and not a `TipRate`, because the menu writes to it
    /// directly and `0` is a legal, meaningful value here — `tip` below turns
    /// it into the checked type. Always starts at none, including on an edit
    /// and on a duplicate: the tip is folded into the stored amount, so the
    /// figure in the field above is already the tipped one, and re-offering a
    /// percentage would apply it a second time.
    /// When the expense happened. Never optional here: the picker cannot
    /// produce "no date", and the log's dateless bucket is for records caught
    /// mid-sync, not for something a user chose.
    @State private var date: Date
    /// What the picker started at, so `save` can tell a deliberate change from
    /// an untouched field. Passing the date back unconditionally would stamp
    /// today onto a dateless record the moment somebody edited its title.
    private let seedDate: Date

    @State private var tipPercent: Double = 0
    @State private var showingCustomTip = false
    @State private var customTipText = ""
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

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
        _selectedPayer = State(initialValue: ExpenseDefaults.lastPayer(in: group, among: roster))
        _title = State(initialValue: "")
        _amountText = State(initialValue: "")
        _splitsEvenly = State(initialValue: true)

        let now = Date()
        _date = State(initialValue: now)
        self.seedDate = now

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
        _selectedPayer = State(initialValue: editing == nil ? nil : expense.paidBy)
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

        // An expense with no stored weighting is an even split, and a uniform
        // weighting is stored as none at all — so the toggle starts on exactly
        // when there is something uneven to show.
        let weights = expense.shareWeights
        _splitsEvenly = State(initialValue: weights.isEmpty)
        _shares = State(initialValue: Self.shares(from: weights, in: group))
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
            Form {
                detailsSection
                paidBySection(roster, avatars)
                splitAmongSection(slices, roster, avatars)
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
            .onChange(of: selectedPayer) { _, newPayer in
                // Most of the time the payer also shares the expense, so
                // preselect them. They can still be toggled back off.
                if let newPayer {
                    selectedParticipants.insert(newPayer)
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
            .sensoryFeedback(.selection, trigger: selectedPayer)
            .alert("Custom Share", isPresented: customBinding) {
                TextField(String(localized: .customSharePercent), text: $customText)
                    .keyboardType(.numberPad)
                Button("Cancel", role: .cancel) { customTarget = nil }
                Button(.setCustomShare, action: applyCustomShare)
            } message: {
                Text(.partialPercentageExplanation)
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
            .errorBanner($errorMessage)
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
    /// Title and Amount are what an expense is made of; Tip, Currency, the rate
    /// and the date are all rows that already have an answer when the sheet
    /// opens, and in the ordinary case — a single-currency group buying a round
    /// today with no service charge on it — not one of the four is touched.
    /// Drawn at the same weight as the amount, they read as five equally
    /// important questions on a form whose entire purpose is one number.
    ///
    /// The rule used to be narrower: *qualifies the amount rather than being
    /// it*, which was true of the first three and made the date look like an
    /// exception when it arrived. It isn't one. What the four have in common is
    /// that they are prefilled and optional, and that is the property worth
    /// drawing — a required field the user must answer and a defaulted one they
    /// may ignore should not carry the same weight.
    ///
    /// One step of the type scale, not a hand-picked size, so Larger Text keeps
    /// scaling all of it. Defined here rather than repeated at the four call
    /// sites because the decision is "these are secondary", and it should be
    /// possible to change that in one place.
    private func qualifier<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().font(.subheadline)
    }

    private var detailsSection: some View {
        Section {
            // Named as optional in the placeholder, because nothing else on
            // screen says so: Save stays enabled with it blank, and a field
            // people believe is required is one they stop to fill in.
            TextField("Title (optional)", text: $title)
                .submitLabel(.next)
                // Pinned, so the placeholder above is free to change wording
                // without breaking the UI tests that reach for this field.
                .accessibilityIdentifier("Title")

            amountRow
            tipRow
            currencyRow
            rateRow
            dateRow
        } header: {
            Text(.expenseDetails)
        } footer: {
            // Echoes back exactly what will be stored, which is the only way
            // the user can catch a mis-parsed separator — or a rate entered
            // upside down — before saving.
            if let summary = savesAsSummary {
                Text(summary)
                    .motionContentTransition(.numericText())
            }
        }
    }

    /// When it happened.
    ///
    /// Last, below the amount and the rows adjusting it. The amount leading the
    /// form was a first-feedback-batch decision and the right one — it is the
    /// only field the form cannot be saved without — so nothing goes above it,
    /// and this is the least often touched of the four rows under it.
    ///
    /// A `qualifier`, like Tip and Currency: the form opens with today already
    /// in it and saves perfectly well without the row being touched, and a
    /// prefilled optional row at the same weight as the one field Save depends
    /// on overstates it.
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

    private var amountRow: some View {
        HStack {
            // Hidden from VoiceOver because the field below carries the
            // same label — otherwise it is announced twice.
            Text(.amount)
                .accessibilityHidden(true)

            Spacer(minLength: 12)

            TextField("0", text: $amountText)
                .focused($amountFocused)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                // Without this the field's only label is its "0"
                // placeholder, which VoiceOver reads as "zero, text field".
                .accessibilityLabel("Amount")
                .accessibilityHint("In \(currencyCode)")

            // Shown as a code rather than a symbol so it stays unambiguous
            // between the currencies that share a `$` or a `kr`.
            Text(currencyCode)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
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
    private var tipRow: some View {
        Menu {
            Button("None") { tipPercent = 0 }

            ForEach(Self.tipPresets, id: \.self) { percent in
                Button(Self.percentText(percent)) { tipPercent = percent }
            }

            Divider()

            Button(.customTip) {
                customTipText = ""
                showingCustomTip = true
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

                    Text(tip.isNone ? String(localized: "None") : Self.percentText(tipPercent))
                        .foregroundStyle(
                            tip.isNone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint)
                        )
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityIdentifier("Tip")
    }

    private func applyCustomTip() {
        guard
            let typed = DecimalInput.parse(customTipText),
            let rate = TipRate(percent: typed)
        else { return }
        tipPercent = rate.percent
    }

    /// Lets an expense be entered in whatever was actually handed over, which
    /// on a trip through two countries is not the currency the group settles in.
    private var currencyRow: some View {
        NavigationLink {
            CurrencyPicker(
                selection: $currencyCode,
                inUse: inUseCurrencies,
                all: Locale.commonISOCurrencyCodes
            )
        } label: {
            // The code alone, not the code and its name. This is a row in a
            // form, and "PLN · Polish Zloty" trailing a label pushes the two
            // into a wrap at accessibility text sizes for a word the user just
            // chose and already knows.
            // Laid out by hand for the reason given on `tipRow`: inside a
            // `NavigationLink`, `LabeledContent` renders its value at body
            // size whatever font is set around it, so this row's PLN came out
            // matching the amount above it — the one figure on this screen it
            // is supposed to be subordinate to.
            qualifier {
                HStack {
                    Text("Currency")
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Text(currencyCode)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Only meaningful when the money wasn't the group's own currency, so it
    /// stays out of the way entirely for the ordinary single-currency group.
    @ViewBuilder
    private var rateRow: some View {
        if isForeign {
            // Demoted with Tip and Currency, even though Save is disabled
            // without it. It is required only *because* a foreign currency was
            // chosen on the row above — it belongs to that choice rather than
            // standing beside the amount — and nothing here has to carry the
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
        Section("Paid By") {
            if members.isEmpty {
                Text(.addMembersFirst)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.objectID) { member in
                    PayerRow(
                        name: member.name ?? "?",
                        avatar: avatars[member],
                        isSelected: selectedPayer == member,
                        onTap: { selectedPayer = member }
                    )
                }
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
                        slice: slices[member].map { $0.formatted(in: group) },
                        onTap: { toggle(member) },
                        onShareChange: { shares[member] = $0 },
                        onCustomShare: { beginCustomShare(for: member) }
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
                // added back later.
                shares[member] = nil
            } else {
                selectedParticipants.insert(member)
            }
        }
    }

    private func share(for member: Person) -> Int? {
        guard selectedParticipants.contains(member) else { return nil }
        return shares[member] ?? Share.full
    }

    // MARK: - Typing in a share

    private func beginCustomShare(for member: Person) {
        customText = String(share(for: member) ?? Share.full)
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
        }
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
                    if !wantsShares { shares = [:] }
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

    /// The weighting as the store and the calculator want it. Empty while the
    /// split is even, which is what leaves the stored expense unweighted.
    private var weightsByID: [UUID: Int] {
        guard !splitsEvenly else { return [:] }

        return selectedParticipants.reduce(into: [:]) { result, member in
            if let id = member.id {
                result[id] = shares[member] ?? Share.full
            }
        }
    }

    // MARK: - Currency

    private var isForeign: Bool { currencyCode != group.currency }

    /// Built once — `commonISOCurrencyCodes` is ~150 entries and looking up a
    /// localized name per row per render would redo that work on every keystroke
    /// in the amount field.
    fileprivate static let currencyNames: [String: String] = {
        let locale = Locale.current
        return Dictionary(
            uniqueKeysWithValues: Locale.commonISOCurrencyCodes.compactMap { code in
                locale.localizedString(forCurrencyCode: code).map { (code, $0) }
            }
        )
    }()

    fileprivate static func currencyLabel(_ code: String) -> String {
        guard let name = currencyNames[code] else { return code }
        return "\(code) · \(name)"
    }

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

    /// The tip as the checked type. An out-of-range `tipPercent` cannot arrive
    /// here — the menu offers only valid values and `applyCustomTip` refuses
    /// the rest — so falling back to `.none` is belt and braces rather than a
    /// silent correction.
    private var tip: TipRate { TipRate(percent: tipPercent) ?? .none }

    /// The entered figure with the tip on top, which is what everything below
    /// converts and stores.
    ///
    /// Applied here, in the currency the money was actually handed over in and
    /// before any conversion, for the reason spelled out in `TipRate.applied`:
    /// the amount is rounded to minor units exactly once, and tipping after
    /// that would round twice and let a split miss its own total by a cent. It
    /// also means a tipped foreign bill records what was really paid — 1 650
    /// HUF, not 1 500 with a euro adjustment bolted on.
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
            parts.append(
                String(
                    localized: "\(Self.percentText(tipPercent)) tip included",
                    comment: "Notes that the stored amount already has a tip in it. The placeholder is a formatted percentage, e.g. '15%'."
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
            && selectedPayer != nil
            && !selectedParticipants.isEmpty
    }

    // MARK: - Save

    private func save() {
        guard let payer = selectedPayer, let amount = finalAmount else { return }
        let foreign = foreignAmount
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let weights = weightsByID

        do {
            if let editing {
                try store.update(
                    editing,
                    title: trimmed,
                    amount: amount,
                    paidBy: payer,
                    splitAmong: selectedParticipants,
                    // Only when it actually moved. An untouched picker passes
                    // `nil`, which leaves the stored value exactly as it was —
                    // including leaving a dateless record dateless, rather than
                    // stamping today on it for fixing a typo in the title.
                    on: date == seedDate ? nil : date,
                    paidIn: foreign,
                    shares: weights
                )
            } else {
                try store.addExpense(
                    title: trimmed,
                    amount: amount,
                    paidBy: payer,
                    splitAmong: selectedParticipants,
                    in: group,
                    on: date,
                    paidIn: foreign,
                    shares: weights
                )
                // Only when adding. An edit corrects something recorded
                // earlier — often much earlier — and letting it rewrite "the
                // last currency used" would prefill the next expense from a
                // receipt two countries ago.
                remember(payer: payer, foreign: foreign)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remember(payer: Person, foreign: ForeignAmount?) {
        ExpenseDefaults.rememberPayer(payer, in: group)
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
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Dimmed rather than hidden for the row that isn't the payer,
                // for the same reason as the split rows: a circle that vanishes
                // makes the list jump as the selection moves.
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
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Marks this person as the one who paid")
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
    /// The member's percentage of a full share, or `nil` when the split is even
    /// and no control should appear at all.
    let share: Int?
    /// What this member will be charged, once there is an amount to divide.
    let slice: String?
    let onTap: () -> Void
    let onShareChange: (Int) -> Void
    let onCustomShare: () -> Void

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
                            if preset == share {
                                Label(preset.formatted(.percent), systemImage: "checkmark")
                            } else {
                                Text(preset.formatted(.percent))
                            }
                        }
                    }
                    Divider()
                    Button("Other…", action: onCustomShare)
                } label: {
                    Text(share.formatted(.percent))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(share == Share.full ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
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
                .accessibilityValue("\(share) percent of a full share")
            }
        }
    }
}

// MARK: - Currency Picker

/// The currency list, as a screen of its own rather than a `Picker`.
///
/// `.pickerStyle(.navigationLink)` pushes a list that cannot be searched, and
/// this one is ~150 rows: reaching HUF meant scrolling past a hundred codes
/// nobody on the trip will ever spend. Search is the entire reason this is
/// hand-rolled, and it matches the localized name as readily as the code —
/// somebody hunting for forint does not necessarily know it is HUF.
private struct CurrencyPicker: View {
    @Binding var selection: String
    /// The group's own currency, the selection, and whatever this trip has
    /// already spent in — see `ExpenseFormView.inUseCurrencies`.
    let inUse: [String]
    let all: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            let used = matches(inUse)
            if !used.isEmpty {
                Section("Used in This Group") {
                    ForEach(used, id: \.self, content: row)
                }
            }

            // The full list stays full, including the codes repeated above.
            // Filtering them out would make the alphabet skip entries for
            // reasons invisible to somebody scrolling it, and a duplicated tick
            // in two sections is the ordinary shape of a suggestions list.
            Section("All Currencies") {
                ForEach(matches(all), id: \.self, content: row)
            }
        }
        .searchable(text: $query, prompt: "Code or name")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A row, not a `Picker` tag: choosing a currency should close the screen
    /// the way a picker's own list does, and a plain selection binding would
    /// leave the user to find Back for themselves.
    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(ExpenseFormView.currencyLabel(code))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if code == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        // The trait below says this to VoiceOver already.
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(code == selection ? [.isSelected] : [])
    }

    /// Matches on the whole label, so "zloty", "PLN" and "Polish" all find the
    /// same row.
    private func matches(_ codes: [String]) -> [String] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return codes }

        return codes.filter {
            ExpenseFormView.currencyLabel($0).localizedCaseInsensitiveContains(term)
        }
    }
}

#Preview("Add") {
    ExpenseFormView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
