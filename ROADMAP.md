# Roadmap

What Dutch might grow into, and what it deliberately won't.

Three constraints decide everything here: the app stays **fast**, stays **native**
(Apple frameworks only, no dependencies), and stays **under 3 MB**. A feature that
can't be built inside those isn't a feature for this app.

On the size budget specifically: pure Swift and SwiftUI with no bundled assets
lands around 1–2 MB, and every framework named below ships with the OS rather
than with the binary — SF Symbols, WidgetKit, AppIntents and CoreSpotlight all
cost approximately nothing. What would actually breach 3 MB is bundled fonts,
image assets, an embedded rate database, or CoreML. None of the work below needs
any of those. Watch the asset catalog, not the code.

**The app is 1644 KB as of 2026-08-28**, down from 2164 KB, which makes the 3 MB
ceiling a formality and 2 MB a close-run thing rather than a comfortable one. It
reached 1252 KB on 2026-07-29 through the four changes below, each measured by
archiving rather than building, and has spent 392 KB since on notifications, the
first-feedback batch and Polish:

| | saving |
|---|---|
| `ASSETCATALOG_COMPILER_OPTIMIZATION = space` | 188 KB |
| `SWIFT_OPTIMIZATION_LEVEL = -Osize` (app **and** DutchKit) | 64 KB |
| `TARGETED_DEVICE_FAMILY = 1` | 432 KB |
| the icon's ring gradient turned vertical | 244 KB |

The last two were trades and were taken deliberately. iPhone-only does not make
the app unavailable on iPad — it installs and runs in iPhone compatibility mode
— it just stops the asset catalog storing a second copy of every icon rendition
for the `pad` idiom, which was 539 KB of exact duplication. And the ring
gradient is a visible departure from `icon.json`; the reasoning is in the
comments in `Dutch/Design/RenderIcon.swift`.

What is left is 932 KB of binary and 212 KB of icon. The binary is the floor for
6 000-odd lines of SwiftUI, and the remaining icon cost is three 1024×1024
renditions that the App Store requires. There is no third act here — further
work would be shaving kilobytes off a number nobody is measuring.

**Raising the deployment target is not a size lever.** Measured 2026-07-29 by
archiving twice against SDK 27.0, `minos` verified with `vtool`: iOS 17 gives a
2128 KB bundle, iOS 26 gives 2112 KB, and `Assets.car` is byte-identical at
1076 KB (both measured before the four changes above). Sixteen kilobytes, all of
it back-deployment thunks in `__text`. Nor is
it a speed lever — SwiftUI and Core Data ship with the OS and run the same code
either way — and Liquid Glass is already active regardless, because adoption
keys off the *linked SDK* rather than `minos`. Raise the floor only to reach a
named API, and say which: today the only two that would matter are
`IndexedEntity` (18.0) and `FoundationModels` (26.0).

---

## At a glance

Every entry on this page, in one place. The prose below each name is the part
that matters — this table says *what*, and the sections say *why*, which is the
half that stops a decision being quietly reversed a year later. Follow the link
before acting on a row.

Shipped entries carry no number: the gaps in the numbering (1–7, 9, 10, 11, 13, 15,
17, 18, 23, 25) are items that shipped, and which number belonged to which was never
recorded.

| № | Status | Name | Description | How it's done, or would be | Blockers |
|---|---|---|---|---|---|
| — | Shipped | [The base](#shipped) | Groups, members, expenses and equal splits; settlement; iCloud sync and QR sharing; foreign-currency expenses converted once at entry. | What 1.0 shipped with. | — |
| — | Shipped | [Edit an expense](#edit-an-expense) | One form both adds and edits, rewriting a record in place. | Replaced delete-and-re-enter, which on a shared group let everyone else watch the balances go wrong mid-fix. | — |
| — | Shipped | [Record a settlement](#record-a-settlement) | **Mark Paid** logs that one member handed money to another. | A payment is an expense paid by A and split among B alone, so `SettlementCalculator` needed no change at all. | — |
| — | Shipped | [Uneven splits, by percentage](#uneven-splits-by-percentage) | Each person's share as a percentage of a full share, 100% by default. | An integer weight overlay keyed by person. Absent weights mean an even split, so every existing expense reads unchanged. | — |
| — | Shipped | [Who am I in this group](#who-am-i-in-this-group) | The device knows which member it belongs to, so balances read *You owe*. | `ExpenseDefaults`, deliberately not the model — syncing it would tell everyone else in the group that they are Marek too. | — |
| — | Shipped | [Duplicate an expense](#duplicate-an-expense) | Touch and hold an expense; the form opens carrying everything over. | The payer is the one field left empty, so Save stays disabled until it is answered — a whole round can't be logged against the wrong person in one tap. | — |
| — | Shipped | [Share a summary](#share-a-summary) | A `ShareLink` over generated text: who owes whom, the total, the log. | Pure string building. `GroupSummary` owns none of its words; the app passes localized strings in, so DutchKit needs no resource bundle. | — |
| — | Shipped | [Your standing on the group list](#your-standing-on-the-group-list) | Each row leads with what you owe or are owed rather than the group's total spent. | Reads the identity the detail screen already writes. The word sequence came off the row at the same time. | — |
| — | Shipped | [App Intents and Shortcuts](#app-intents-and-shortcuts) | New Expense, Add Expense and Check Balance, from Siri, Spotlight and the Action button. | Who paid is the device's identity, never a parameter. This is what moved both stores into the app group. | — |
| — | Shipped | [Spotlight indexing](#spotlight-indexing) | Groups findable by name or word sequence from the Home Screen. | Groups only, never expenses. The whole set is rewritten on every change, triggered by saves *and* remote changes — neither is a superset of the other. | — |
| — | Shipped | [The first-feedback batch](#the-first-feedback-batch) | Five fixes from one Reddit weekend: Undo on settle-ups, an optional title, the cursor in the amount, a searchable currency picker, Add Expense in the bottom bar. | Only the Undo was a defect — reversing a settlement previously meant a red **Delete** on a list where deleting destroys an expense. | — |
| — | Shipped | [Open the last group on launch](#open-the-last-group-on-launch) | An optional setting; a cold launch reopens the group you were in. | Cold launch only, from `scene(_:willConnectTo:)`. A foreground restore would make it impossible to stay on the group list across a backgrounding. | — |
| — | Shipped | [The empty Members section](#the-empty-members-section-said-the-same-thing-three-times) | Dropped the grey placeholder row that repeated what the button beneath it already said. | The header stayed a noun: a verb there is announced by VoiceOver immediately before the button repeating it. Whether a new group should be one empty state rather than three is still open. | — |
| — | Shipped | [Reduce Motion](#reduce-motion) | `accessibilityReduceMotion` honoured across all nine content transitions. | One helper, `motionContentTransition(_:)`, so `grep` answers "does everything honour it" in a line. Value animations deliberately stayed. | App Store listing doesn't claim it yet — metadata, not a build |
| — | Shipped | [Tip, tax and service charge](#tip-tax-and-service-charge) | One percentage added on top of the entered amount, applied before the split. | Multiplies the figure as typed, before any conversion, so the bill is rounded exactly once and a split still adds back up. Capped at 100% for the typo, not the tipper. | Nothing is stored, so a tip can't be edited afterwards |
| — | Shipped | [Settle part of a debt](#settle-part-of-a-debt) | Tap the amount on a suggested payment and enter what actually changed hands; **Mark Paid** still clears the whole thing in one tap. | The store always took an arbitrary `Money` — only `TransferRow` insisted on the full figure. It records a payment, never a plan: the transfer list is recomputed from balances and may re-pair under a partial. | Capped at the suggested amount, so overpaying means overpaying in cash |
| — | Shipped | [Choose the date on an expense](#choose-the-date-on-an-expense) | A date picker on the expense form and on the settle-up sheet, so a trip already under way can be entered. | `Expense.date` had existed since v1 and the log already sorted and bucketed on it, so this was a `date:` parameter with a default and one Form row. Bounded at today. | An edit only moves the date when the picker was actually touched |
| — | Shipped | [Categories](#categories) | An optional category on an expense, drawn as a glyph in the log. | An optional `symbolName` on `Expense`, same trick as the group's — SF Symbols ship with the OS, so a full set costs nothing in the bundle. Nothing in the settlement reads it. | Doesn't group or filter the log yet; it labels rows |
| — | Shipped | [Member avatars from SF Symbols](#member-avatars-from-sf-symbols) | A member can wear a glyph instead of their initials. | An optional `symbolName` on `Person`, and the group's curated set renamed `Emblem` and shared rather than copied. | — |
| — | Shipped | [Archive a group](#archive-a-group) | Finished trips fold into one collapsed row instead of sitting in the list forever. | An optional `archivedDate` on `ExpenseGroup` and a split of the same unfiltered fetch. | Archived groups still count against the free limit, deliberately |
| 8 | Not started | [Home screen widget](#8-home-screen-widget) | "You owe €120 · green-moon-tea", read from the same store. | The expensive half is already done — the stores and `ExpenseDefaults` live in the app group. Depends on **Who am I**. | ~200 KB extension binary |
| 12 | Shipped | [Exact amounts in a split](#12-exact-amounts-in-a-split) | Enter what each person owes when the receipt already says. Fixed rows come off the top; the remainder divides among the rest. | Cent-weights in the weighting that already existed — no model version, no promote, and an older build divides it correctly rather than falling back. | A tip is no longer separable from the items once saved; it reopens folded in |
| 16 | Shipped | [Several people paid](#16-several-people-paid) | Several payers on one trip through the form, saved as one ordinary expense each. | The workaround being exactly correct is what made it cheap: the app performs it. No model change, no calculator change, nothing new for an old build to miss. | Buys entry convenience, not a tidier log — you still get one row per payer |
| 19 | Not started | [The Nearby button](#19-the-nearby-button) | A **Nearby** button offering the cafés and restaurants within a hundred metres as the title. | `MKLocalPointsOfInterestRequest`, not `MKLocalSearch.Request` — the latter searches for text. A button and never a prefill, which answers the permission timing and keeps the title optional at once. Must degrade quietly when roaming is off. | A location permission prompt, at the worst possible moment |
| 20 | Not started | [The currency, from the country the chosen place is in](#20-the-currency-from-the-country-the-chosen-place-is-in) | The expense form defaults to the local currency. | `Locale(identifier: "und_PL").currency` — no embedded table, and the country comes free from the picked `MKMapItem`, so no `CLGeocoder`. The trap is carrying the previous country's *rate* across; `onChange(of: currencyCode)` already handles it, so let it run. | Rides on **19**: `Locale.current.region` is the region setting, not where you are |
| 21 | Not started | [The place on the expense](#21-the-place-on-the-expense) | The chosen name and its coordinates, stored on the expense; the row in the form opens the pin in Apple Maps. | A pin glyph marks the row in the log, and the name appears in words only once the title no longer says it. Grouping the log by place is still open — the log is already grouped by day. | Dutch 8 and Dutch 9, each with a promote of its own; **12** and **16** shipped without a model version, so there was nothing to pair with. **Dutch 9 is not promoted yet.** A shared place doesn't come back out, so it needs **19**'s explicit tap, plus a privacy-label line |
| 22 | Not started | [iPad and Mac](#22-ipad-and-mac) | "Designed for iPad" is a checkbox; native iPad, Catalyst and macOS are real work. | Sync needs nothing — CloudKit is per Apple Account. Two things bite: the app-group identifier is spelled differently on macOS, and share acceptance is a different method again. Both fail silently. | 432 KB for native iPad, being a saving already taken |
| 24 | Not started | [An iMessage app](#24-an-imessage-app) | Assign a group to a group chat and manage its expenses inside Messages. | A target in this bundle, not a second app. The app group and `Intents/` already pay for most of it. May be worth more as a fix for the QR join dead-end than as a way to enter expenses. | App size — a second binary, plausibly past 2 MB with the widget. And whether an extension's writes export before the host app next launches is unverified |
| 14 | Shipped | [Measure contrast, then claim it or fix it](#14-measure-contrast-then-claim-it-or-fix-it) | Measured: green failed at 2.22:1 on white, well under the 3:1 it needed. Light appearance now uses Apple's high-contrast pair. | Measured on both grounds the amount appears over. `Standing.tint` only — dark appearance already passed and was left alone. | Listing still doesn't claim it; that's metadata, not a build |
| — | Not planned | [Receipt photos](#not-planned) | | Breaks all three constraints at once — CloudKit assets, sync weight, storage, and an image pipeline. | — |
| — | Not planned | [Live exchange rates](#not-planned) | | Rates are frozen at entry deliberately; fetching them adds a network dependency and a cache in order to reintroduce the drift that decision removed. | — |
| — | Not planned | [A charts tab](#not-planned) | | Swift Charts is system-provided, so technically free — and nobody opens it twice for a group with eleven expenses in it. | — |
| — | Not planned | [An expense with no group](#not-planned) | | The need is real, the shape isn't. Answered instead by a **"Split with…"** fast path that makes a two-person group in one step. | — |
| — | Not planned | [A backend, accounts, or login](#not-planned) | | The absence of one is the design. | — |

---

## Shipped

**The base:**

- Groups, members, expenses, equal splits
- Settlement (balances + a short list of payments that clears them)
- iCloud sync and group sharing by QR code
- Expenses entered in a foreign currency, converted once at entry

**Added since:** everything below. The first four were built together because two
of them shared a single Core Data version bump and doing that migration twice
would have been worse than doing it once; only the group's symbol and colour
have needed a model change since. The reasoning is kept here because each one
had a non-obvious decision behind it.

### Edit an expense

The only correction used to be swipe-to-delete and re-enter, which on a shared
group means the other person watches an expense vanish and reappear over
CloudKit — with a window in between where the balances are wrong. One form now
adds and edits, rewriting one record in place and leaving its date alone.

*Cost: zero bytes. No model change.*

### Record a settlement

Nothing let someone say "I paid Anna the 40 back", so a long-running group only
ever accumulated.

The useful property: a payment was already expressible in the existing maths. A
pays B is an expense **paid by A, split among B alone** — which nets A up and B
down by exactly the amount, and settles them. `SettlementCalculator` needed no
change at all. The only new state is a flag so the row renders as a payment
rather than an expense, and so it stays out of Total Spent.

*Cost: one optional Bool. Model v3.*

### Uneven splits, by percentage

Equal-only was the ceiling on real use. Two cases from one real trip:

- a train ticket where one of six people has a 51% student discount;
- a hotel for six — two couples in two rooms, two people in singles — where all
  four rooms cost the same and each half of a couple should pay half a room.

Both are the same operation: **what someone pays relative to a full share**. So
the control is a percentage, 100% by default, set per expense from a menu of
100 / 75 / 50 / 25 with a typed value for anything else. The discount is a fact
about *the ticket*, not about the person — a student pays full price for beer —
so this lives on the expense and nowhere else.

Percent rather than a multiplier because reductions are the common case: 50% for
a couple, 49% for a discounted fare. `0.49×` cannot even be typed into a stepper.

The percentages across a split do not add up to 100 and are not meant to — six
people with one discounted fare comes to 549%. Nothing in the UI shows that
total; the rows show amounts in the group's currency, and those do add up.

Stored as an integer weight overlay keyed by person, with `splitAmong` still
authoritative for *who* is in the split. Absent weights mean an even split, so
every existing expense keeps reading exactly as it did.

*Cost: one optional String. Model v3, shared with the settlement flag. Logic
lives in DutchKit and is testable without a simulator.*

### Who am I in this group

There was no notion of which member is the person holding the phone, so every
balance read in the third person. "You owe 120" is a better sentence than "Marek
owes 120", and it is a prerequisite for the widget.

Lives in `ExpenseDefaults` alongside `lastPayer` — same reasoning: it is a fact
about the device, not about the group, and syncing it would tell everyone else in
the group that they are Marek too.

*Cost: a `UserDefaults` key. No model change.*

### Duplicate an expense

Buying rounds was the case. Four people take turns at the bar, and each round is
the same title, the same amount and the same split — everything except who paid.
That was four full trips through the form, and the payer prefill actively worked
against you: `ExpenseDefaults.lastPayer` suggests whoever paid last, which in a
round is precisely the person who is *not* paying now.

Touch and hold an expense → **Duplicate** → the form opens carrying everything
over. Four rounds are one full entry and three pairs of taps. It also catches the
everyday repeat on a trip: the same coffee, the same parking, the same ticket.

Duplication rather than a cleverer prefill, deliberately. Guessing who pays next
is fortune-telling; copying what the user already entered is not.

The payer is the one field deliberately left empty, which also leaves Save
disabled until it is answered. Carrying the original over would mean a whole
round could be logged against the wrong person with a single tap — and the payer
is the only reason this screen is open. Everything else is a copy, including the
currency and the rate it was captured at, so a duplicated foreign receipt
converts exactly as the original did rather than at whatever rate was last used.

Long-press rather than a swipe action or a row button: this is wanted often
enough to exist and read often enough that it shouldn't take up space in the
list. Payments are excluded — settling up is recorded from the section above,
and paying the same debt twice is a mistake rather than a shortcut.

*Cost: zero bytes. No model change; `GroupStore.addExpense` already took every
field this needed.*

### Share a summary

`ShareLink` over a generated text block: who owes whom, the total, the expense
list. Pure string building, zero framework cost, and it matches how people
actually settle — pasted into the group chat.

### Your standing on the group list

The list showed each group's *total spent*, which is a fact about the trip and
not about you — the number you actually came for was one tap away, on every
group. Once the device knows who you are, the row leads with what you owe or are
owed, tinted and captioned exactly as the member rows on the detail screen are.

The total gives up its place rather than sharing the corner with the personal
figure: two amounts side by side make each of them something to decode. Groups
where identity hasn't been set read exactly as they always did.

The word sequence came off the row at the same time. It is a label for pairing a
new phone, printed next to the QR code on the share screen; on the list it was
taking the line the standing now uses.

*Cost: zero bytes. Reads the `ExpenseDefaults` identity the detail screen already
writes, and the standing itself came out of `MemberBalanceRow` into a shared type
so both screens phrase and colour a balance identically.*

### App Intents and Shortcuts

Every one of the five seconds this app exists to save was being spent inside it:
unlock, find the icon, tap the group, tap Add Expense. Three actions now reach
past all of that — from Siri, the Action button, Spotlight, the Shortcuts app,
and a long press on the icon.

**New Expense** opens the form on a group. **Add Expense** records one without
launching at all. **Check Balance** answers the only question anybody opens a
bill-splitting app to ask. All three default to the group you last opened, which
is what makes them worth having: "add an expense", said mid-trip, means *this*
trip, and having to name the group every time turns a five-second entry into a
conversation. With exactly one group on the phone it doesn't even need that.

Two decisions carried real weight.

**Who paid is the device's identity**, not a parameter. A payer picker that
could not be narrowed to the members of the chosen group would offer everybody
from every group, and recording an expense against someone who isn't in it is a
wrong balance that nothing on screen would flag. Asking the user to say who they
are once is the cheaper mistake. Without an identity the intent refuses and
names the gesture that fixes it.

*Correction, checked against the iOS 27 SDK on 2026-07-29:* this was written
here as "iOS 17 has no `@IntentParameterDependency`", which is wrong — it is
annotated `@available(iOS 17.0)`, and only its `Hashable` conformance is 18.0.
So the narrowed picker may in fact be reachable at the current floor. Nobody has
tried it; the identity decision stands on its own merits either way, but the
stated blocker was not real.

**Amounts are in the group's own currency.** A foreign receipt needs a rate,
rates are frozen at entry on purpose, and there is no way to ask "at what rate?"
in a voice flow without guessing — which is precisely the failure that decision
exists to prevent. Foreign receipts go through the form, and so do uneven splits.

`AddExpenseIntent` gets no confirmation step, deliberately: confirming would
spend the time this exists to save. Instead the reply states the figure and the
group it landed in, phrased through the same `Standing` type the screens use, so
a mishearing is audible immediately — and a wrong entry is one swipe to delete.

The word sequence became useful here for the first time since it was printed
next to the QR code: `EntityStringQuery` resolves "green moon tea" as readily as
"Berlin Trip". It still grants nothing — it searches groups the device already
has, and access comes only from the CloudKit share.

**The stores moved into an app group** as part of this, along with
`ExpenseDefaults`. Nothing here needed it; the widget below does, and a widget
is a separate process that cannot open the app's own container. Doing it once
the app has users would mean abandoning every local store, so it was done while
that costs nothing.

*Cost: a few KB of intent definitions. `AppIntents` ships with the OS. No model
change; `GroupStore.addExpense` already took every field this needed.*

### Spotlight indexing

The App Intents above put three *actions* in Spotlight; they left the groups
themselves unfindable. Typing "Berlin" on the home screen now lands in the trip.

**Groups only, not expenses.** An expense has nowhere of its own to open — there
is no expense screen, so every hit could only land on its group anyway — and
titles like "Dinner" or "Taxi" repeat across every trip anybody has ever taken,
which turns one useful result into forty indistinguishable ones. Groups are few,
individually named, and each one is already a destination.

**The whole set is rewritten on every change rather than diffed.** That sounds
wasteful and isn't: a device holds a handful of groups. The alternative is
remembering which identifiers were written last time in order to know which to
delete, which is bookkeeping living outside Core Data that would drift from it
the first time a save failed halfway. Clearing by domain identifier means the
index cannot hold a group that no longer exists, whatever happened.

Reindexing is triggered by **both** `NSManagedObjectContextDidSave` and
`NSPersistentStoreRemoteChange`, because neither is a superset of the other: a
group created here never produces a remote change, and one deleted on another
device never produces a save here. Watching only saves would be the same mistake
`@FetchRequest` exists to prevent — the index would quietly stop tracking
anything that arrived over CloudKit. A sync arrives as a run of notifications
rather than one, so they coalesce over 500 ms.

Two things that would have failed silently: items **expire after a month** by
default, so a trip nobody opened would fall out of Spotlight — which is exactly
the group somebody would go looking for this way; and indexing is skipped under
`-uitesting-reset`, since test fixtures reaching the device's real index would
outlive the run that created them.

The word sequence is indexed whole and never split. "green" would otherwise
match every trip that happened to draw that word. It remains a label and not a
credential — searching finds only groups the device already has.

*Cost: zero bytes. `CoreSpotlight` ships with the OS. No model change.*

### The first-feedback batch

One post on Reddit put the app on 800 phones and produced eleven requests in a
weekend. Five of them were small, and they shipped together on 2026-08-20
because they are all the same kind of thing: friction in the twenty seconds
somebody actually spends in this app, found by people using it at a table rather
than reading the code.

**Undoing a settle-up** was the only one that was a defect. "Mark Paid" writes a
reimbursement, and the expense list applied a blanket `onDelete` to every row —
so the one way back out of an accidental settlement was a red **Delete**, on a
list where deleting is how you destroy an expense you typed. It worked, and it
read as data loss; the reporter tried it expecting to lose the row and was
surprised to get the debt back. The payment rows now carry a `swipeActions` of
their own labelled **Undo**. Still destructive, still red — a record does go
away — but the word now describes what happens.

**A title is no longer required.** An expense is a figure, a payer and a split;
those three are what a balance is made of, and the title is a label on top of
them. Requiring one meant standing at a bar typing "Beer" before the app would
take the number. A blank title is stored as `nil` rather than `""` — every
screen already falls back on a *missing* title, and an empty string is not
missing: it satisfies `title ?? "Untitled"` and draws a blank line where the
fallback belongs. Untitled rows lead with the payer instead of with the word
"Untitled", which says nothing and would say it again on every row; `PaymentRow`
had already established that a one-line row reads fine among two-line ones.

**The cursor starts in the amount**, which follows from the above: it is now the
only field the form cannot be saved without, and it raises the decimal pad where
the title raised a full keyboard on a screen whose purpose is a number.

**The currency picker is searchable**, and remembers what the group has spent
in. Half of this was already built — `lastCurrency` has always prefilled the
last-used currency, and the group's own has always been pinned to the top — but
`.pickerStyle(.navigationLink)` gives no search field, and reaching HUF meant
scrolling past a hundred codes nobody on the trip will spend. It is a hand-rolled
list now, matching on the localized name as readily as the code, with the four
currencies this group has actually used in a section above the full register.

**Add Expense moved to the bottom bar.** It is the one thing on the detail
screen anybody does more than once a trip, and the top-right corner is the
furthest point on a 6.9" phone from the thumb holding it. Edit Group and Share
stayed where they were: moving the whole toolbar down relocates the problem and
costs the grouping that says which of the three is the point.

*Cost: 36 KB archived, 1516 → 1552 KB, all of it binary — `Assets.car` is
unchanged at 212 KB. No model change; the four features that touch storage all
ride on `UserDefaults` or on attributes the model already had.*

### Open the last group on launch

Requested by somebody who lives in one group at a time, which on a trip is
everybody. Most of it already existed — `ExpenseDefaults.lastOpenedGroupID` was
being recorded for the Action button and the Home Screen action, and
`AppRouter.open` is how anything outside the view tree pushes a screen — so this
was the wiring, a switch in Settings, and one decision that only appeared once it
could be used.

**A setting, defaulted off**, matching how notifications work here: the app does
not change where it opens until asked. `bool(forKey:)` returns `false` for a key
never written, so "off" needs no registration. The key lives in `ExpenseDefaults`
and is `internal` rather than `private`, because the `@AppStorage` binding in
`SettingsView` and the launch site have to spell it identically — the same reason
`QuickAction.newExpense` exists once.

**Cold launch only, and that is the whole of the interesting part.** The restore
runs from `scene(_:willConnectTo:)`, which fires when a scene *connects*. Coming
back from the background therefore restores nothing, and the first report after
building it was exactly that: toggle on, leave the app on the group list, tap the
icon, get the group list. That reads like a bug and isn't one.

Moving the call to a `scenePhase` hook is the obvious repair and it is wrong.
Returning from the background already puts you back in the group you were in,
because the navigation path never left memory — so the *only* screen a foreground
restore could change is the one where you had deliberately navigated back to the
list. And `lastOpenedGroupID` is never cleared when you do that, because the quick
action and Siri both need it to keep meaning "the trip I'm on". A resume restore
would therefore make it impossible to stay on the group list across a
backgrounding. A time-thresholded version was considered and declined on
2026-08-28: it buys a rarer version of the same fight with the user, at the cost
of a stored `Date` and behaviour nobody can predict from the switch's label.

The consequence is that the feature fires seldom, since iOS rarely terminates
apps. That is the honest trade, and the footer says so rather than promising more
than it does — *"When Dutch starts fresh…"*, not *"when you open Dutch"*.

Two smaller things the build settled. Precedence is one line: the restore runs
last in `willConnectTo` and only when `AppRouter.shared.destination` is still
`nil`, so a quick action, a Spotlight result or an intent always wins. Accepting
an invitation turned out not to be the hazard it looked like — acceptance is
asynchronous and never writes to the router at all, and a first-time member has no
last-opened group to restore. And the id is resolved through `GroupLookup` rather
than handed to the router raw, because `followRouter` answers an unresolvable id
with *"That group isn't on this device."* — the right answer for a tap, and the
wrong one for a launch nobody asked a question with.

*Cost: 2.7 KB of `__text`, shared with the entry below. Three strings in two
languages. No model change.*

### The empty Members section said the same thing three times

Reported as "this feels redundant", about a section that on first launch read: a
header saying **Members**, a grey row saying *Add members to start splitting
expenses.*, and a button saying **Add Member**. Three lines, one instruction. The
complaint was right.

The suggested fix was to make the header the instruction — *Add Members* while
empty, reverting to *Members* once there are any — and that is the one of the
three that should not have moved. A section header is the context VoiceOver reads
before every row beneath it, so a verb there is announced immediately before the
button that repeats it, which makes the redundancy louder rather than quieter for
the people least able to skip past it.

**The grey row went instead**, being the line carrying no information the button
doesn't. The precedent was already in the same file: `expensesSection` shows a
placeholder **or** an action, never both, and `membersSection` was the one place
that stacked the two. So this applied an existing rule rather than inventing one.

Removing it orphaned `addMembersToSplitExpense`, which had exactly one call site.
The key came out of the catalog in both languages and out of `LocalizableTests`,
where the keys and their expected translations are two positional arrays — an
entry has to leave both at the same index, or every assertion after it compares
the wrong pair.

**The larger question underneath it is still open.** A brand-new group draws three
empty containers in a row — *Nothing spent yet*, the members placeholder, *No
expenses yet.* — each individually reasonable and collectively a screen that
announces its own emptiness three times before offering anything to do about it.
Cutting the members row answered the report. Whether a group with no members and
no expenses should be one empty state rather than three is not settled.

*Cost: negative in source — one `Text`, one branch and one string removed.*

### Reduce Motion

Nothing in the app read `accessibilityReduceMotion`, which made it the one
accessibility gap that was real work rather than a measurement. It is now
honoured, through one helper rather than an environment read in every view:
`motionContentTransition(_:)` in `Views/Components/ReduceMotion.swift` passes
`.identity` when the setting is on, and all nine content transitions route
through it. `ErrorBanner` reads the value directly, because what it needs to
drop is a `.transition`, not a content transition.

**The single funnel is the point.** A bare `.contentTransition` is now absent
from the app, so `grep` answers "does everything honour the setting" in one
line, and a new one added later stands out as the site nobody audited. Scattering
`@Environment(\.accessibilityReduceMotion)` across nine views would have worked
once and rotted on the tenth.

**Two kinds of motion were removed, and one kind of animation deliberately was
not.** `.numericText()` rolls every digit of a balance whenever the figure
changes — including changes the user did not initiate, arriving from a CloudKit
import while they are reading the screen — and `.symbolEffect(.replace)` swaps a
glyph by scaling one out and the next in. Both go. The banner's slide up from
the bottom edge becomes a plain fade rather than nothing at all, because unlike
a balance changing under you that one *is* an event, and it has to be noticed to
be read before it clears itself six seconds later.

What stayed is the `.snappy` value animations — a balance easing from red to
green, a picker's selection moving. Those animate colour and layout, and the
setting targets motion rather than change; Apple's guidance is to substitute
cross-fades, not to freeze the interface. That is a judgement call and it is
reversible in one line in the helper if it turns out to be the wrong one.

**A correction, because this page had it wrong.** The second effect was
described here as "the group list's `.spring(response: 0.35, dampingFraction:
0.8)`". That spring is in `ErrorBanner.swift` and always was; `GroupListView`
uses `.snappy`. The count of "22 animation sites" was reached the same way — by
counting every animation rather than every piece of *motion*, which is ten. Read
the code before quoting this file's numbers back at it.

Worth keeping: the rolling digits were never only an accessibility problem. They
are why an App Store screenshot captured a few seconds after launch caught ghost
numerals mid-transition, and why the capture script waits ten seconds.

**The listing is the outstanding half.** The code supports Reduce Motion; the
App Store accessibility labels do not yet claim it. A label is a claim, and this
one is now true — but claiming it is a metadata change, not a build.

*Cost: 2.1 KB of `__text`, and zero archived bytes — the app measured 1660 KB
before and after, the `__TEXT` segment padding absorbing all of it. No model
change.*

### Tip, tax and service charge

The tractable half of "scan a receipt with the service charge split out": one
percentage added on top of the entered amount, applied before the split, echoed
back in the same *saves as* line that already reports a foreign conversion. It
is a restaurant feature in an app whose commonest expense is dinner, and it
needs no camera at all.

**One percentage, not three named ones.** The moment there is a separate tip and
a separate tax, somebody has to answer whether the tip is computed on the
pre-tax or the post-tax total — a question real people argue about at real
tables, and this app exists to delete that arithmetic rather than to host it.
One figure covers a European service charge, a UK discretionary 12.5% and a US
tip; anyone wanting two of them adds them together or types the final total.

**A percentage and never an amount.** "Make it 60" is the same trap as **12**: a
single field where `50` might mean 50% or 50 złoty. That duality is refused
there and is refused here too, so a flat-amount tip waits and reuses whatever
control **12** lands on rather than inventing a second answer now.

**It multiplies the figure as typed, before any conversion**, which is the one
decision the code actually forced. An expense is rounded to minor units exactly
once — in `Money.init(amount:)` for an ordinary expense, `ForeignAmount.converted`
for one paid abroad — and that single rounding is what keeps `Money.split`'s
promise that the shares add back up to the total. Scaling a `Money` instead
would round twice, and a three-way split of a tipped bill could miss its own
total by a cent. `TipRateTests.tippedBillSplitsExactly` is the guard.

It also means a tipped foreign bill records what was really handed over — 1 650
HUF, not 1 500 with a euro adjustment bolted on afterwards. That falls out of
`ForeignAmount.amount` being a `Double` in major units, which it is because a
third of the world's currencies have no minor unit.

**The cap is 100%, and it is there for the typo rather than the tipper.** A
missed decimal point turns 15% into 1500% and a 47.30 dinner into 756.80, which
is a plausible-looking number nobody catches until the balances are wrong.
Negative is refused for a related reason: a percentage that *reduces* a bill is
a discount, a different feature wearing this one's control, and a stray minus
would quietly lower a total everybody else is splitting.

**Nothing is stored.** The tip folds into `amount`, so there is no model change
and no CloudKit promote — but unlike the exchange rate, which keeps
`originalAmount` as provenance, this keeps none. Reopening an expense shows the
tipped figure with the tip back at *None*: lossless if you re-save, but the tip
cannot be adjusted afterwards and no row can read *"incl. 15%"*. An optional
`tipPercent` is the obvious passenger for the version 8 that **12** and **16**
will need anyway.

*Two things this turned up, both bigger than the feature.* The `saves as` footer
had **never been localized** — `savesAsSummary` returns a `String`, and
`Text(_: String)` is the non-localizing initializer, so every Polish phone read
"Saves as 47,30 zł" in English with nothing anywhere to say so. It is the exact
failure the Localization section already names, and it still got missed, which
is worth knowing about the rest of the codebase. And the fix for it nearly
shipped broken in a way described under **Adding the next language** below.

*Cost: 10.5 KB of `__text` and 1.2 KB of strings across both languages. The
archive did not move — 1660 KB before and after, `__TEXT` segment padding
absorbing all of it. No model change.*

### Settle part of a debt

Asked for by mail on 2026-08-29, in one sentence: *A owes B $1000, and B wants
to pay it in five instalments of $200.* **Mark Paid** wrote the whole transfer
or nothing.

**The store had always been able to do this.** `GroupStore.recordPayment` takes
an arbitrary `Money` and writes an ordinary expense — paid by the person
settling, split among the person being paid, flagged `isReimbursement` so it
stays out of Total Spent. Nothing in it compares the amount to the debt. The
limitation was a single line in `TransferRow`, where the button handed the whole
of `transfer.amount` to its action. So this was a control and a sheet: no model
version, no CloudKit promote, no new attribute — the cheapest entry in the
section it came from, and the only one a user had asked for in as many words.

Undo arrived free. A partial payment is a payment row like any other, so the
swipe action added in the first-feedback batch backs each of the five out
individually. `GroupStoreTests.undoingOneInstalment` pins that.

**It records a payment; it does not create a plan.**
`SettlementCalculator.transfers(settling:)` is greedy and recomputed from
balances on every render: largest creditor against largest debtor, names
breaking ties. It cannot remember that a row was half paid, because there are no
rows to remember.

With two people that is invisible — 1000 becomes 800 and the list says what the
user expects. With two on each side it is not. Balances of A −500, D −300,
B +500, C +300 read as *A→B 500* and *D→C 300*; A pays B 200, the four remaining
balances are 300 apiece, and the tie breaks by name into something that can pair
A with C and D with B. Every figure is correct and the pairing has changed: the
row somebody was halfway through paying is gone.

Keeping it would have meant making the transfer list durable state — recording
that *this* debt is being paid down, alongside the balances that already say so
in a form which cannot contradict itself. That is a second source of truth for
one fact, and the first time the two disagreed the balances would be right while
the plan would be what the user was reading. So the feature is *record what was
actually handed over*. Five payments of $200 do clear the debt; the app simply
never narrates them as instalments.

**The control is a button on the amount, and it was going to be a `Menu`.** The
open question when this was written was which affordance hangs off the figure.
A menu lost on arithmetic: its only entry would have been *Settle Part…*, since
**Mark Paid** already sits in the row and duplicating it there is noise — and a
one-item menu is a button that costs an extra tap. The sheet it opens is
prefilled with the full amount anyway, so tapping the figure gives up nothing.
The button below it still clears the whole transfer in one tap, which is the
common case and the thing the screen exists for.

**Splitting the amount out of the row cost an accessibility fix.** `TransferRow`
combined names and amount into one element with a hand-written label — *"You pay
Bob $500"*. A control folded into a combined element is a control VoiceOver
cannot reach, so the row would have read correctly and the action would have
been gone. The label is now two elements, and the two three-argument strings
behind the old one are deleted from the catalog. `Text(payer)` was also passing
a `String` to the non-localizing initializer, so *"You"* had never had a key at
all — the failure named under **Localization**, found again on a line being
rewritten for another reason.

**Overpaying is capped, and the precedents disagreed about it.** The tip cap is
capped for the typo rather than the tipper, which argued for clamping the field
to the suggested amount. But handing over 1200 against a debt of 1000 and taking
change is ordinary behaviour at a table, and the maths needs no help with it —
the recipient owes 200 afterwards and the next render says so. Clamping won on
the reading that a figure above the suggestion is more often a slipped decimal
than an intention, and that the way to overpay is to overpay, in cash, and let
the app describe what is left. Confirm is disabled above the cap and the footer
names the cap before it is reached, so the refusal reads as a stated rule rather
than a broken control.

**The field prefills full, and iOS 17 will not select it.** Prefilling is the
inverse of the reason **Duplicate** leaves the payer empty: there the empty
field is the one that must be answered deliberately, here the prefilled one is
the entire point of the sheet. It should arrive selected, so the first digit
typed replaces it — and `TextField(text:selection:)` is iOS 18. The stand-in is
a clear button in the row, which is what every iOS text field already has;
without it, overriding a four-digit default is four backspaces before a single
digit is typed. Revisit when the deployment target moves.

**`DecimalInput` came out of `ExpenseFormView` on the way.** Reading a
`.decimalPad` field and writing a figure back into one were a private pair on
the expense form — and they only work as a pair, because the formatter must
never emit a grouping separator the parser would read back as a different
number. A second screen prefilling a currency field would have copied them, and
the copy is where the comma case gets dropped from one of them. They are in
DutchKit now, with the round trip asserted in both an English and a Polish
locale, which is the first test either half has ever had.

*Cost: unmeasured. A sheet, a decimal field and ten strings in both languages;
no model change and no CloudKit promote.*

### Choose the date on an expense

Asked for by mail on 2026-08-31, alongside categories, and phrased as
*grandfathering*: the form stamped today and offered no way to say otherwise, so
anything that happened before the app was opened could not be recorded as having
happened then.

The case was adoption rather than correction. Somebody installs Dutch on the
third day of a trip and wants days one and two in it. Those two days went in
dated today — six receipts under one heading, in the wrong order, on the screen
whose entire organising idea is *Sat 12 July*. The alternative was not entering
them at all, which is the same as not adopting the app until the next trip.

**`Expense.date` had been there since v1.** An optional `Date` in the shipped
model, `Expense.request(in:)` already sorting on it descending, and
`GroupDetailView` bucketing that sorted log into days in a single pass. So a
backdated expense sorts and groups correctly with nothing changed: this was a
`date:` parameter on `GroupStore.addExpense` — defaulted to `Date()`, so the
intents and `ScreenshotSeed` are untouched — and one Form row. No model version
and no CloudKit promote, cheap for the same reason **Settle part of a debt**
was: the storage was built general and only the form was narrow.

**The future is not offered, and that was the open question.** An expense is
something that happened, which argued for a bound at today. Two things argued
against a hard one: a prepaid booking is a real thing to log, and *today* is
ambiguous for a group spread across timezones, which is the group this app is
for. The timezone half turned out not to survive contact: the bound is per
device, and a phone in Tokyo already believes it is the 12th, so nobody is
prevented from entering their own day. That left prepaid bookings against the
fat-fingered year — and the tip cap had already settled that trade, a bound
being for the typo rather than for the tipper. A wrong year is the worst error
available here, because it sorts to the top of the log and stays there.
Decided 2026-08-31: bounded at today, revisit if anybody asks for the booking.

**The bound is `max(seedDate, Date())`, not `Date()`.** A stored date already
beyond now — an older client, a skewed clock — would sit outside a bare range,
and `DatePicker` resolves that by clamping. That is a silent edit to somebody
else's record performed by opening a form, which is exactly what the rule below
exists to prevent. Widening the range for a value that is already there costs
nothing: it still cannot be *chosen*, only kept.

**`update` now moves the date, and its comment used to say the opposite** —
*"`date` is deliberately untouched: an edit corrects what was recorded, it does
not move the expense to today."* That was written when nothing could state a
date, so the only thing an edit could do to one was reset it silently. Once the
form carries the field the reasoning inverts: a wrong date is exactly what
somebody reopens an expense to fix.

The invariant that survived is the one that mattered — **an edit never moves the
date implicitly**. `update`'s parameter is optional, the form seeds the picker
from the stored value and remembers what it seeded, and passes a date only when
the two differ. So fixing a typo in a title leaves the day alone, and a dateless
record caught mid-sync stays dateless rather than being stamped with today by an
edit that never mentioned it. `updateWithoutDateLeavesItAlone` pins both halves.

**A duplicate starts today; an edit reopens on its own day.** The duplicate is
the interesting one, because its stated principle is to carry everything over
except the payer. The date is the exception: a round logged tonight from last
Tuesday's receipt would land in Tuesday's bucket, which is the precise filing
error this feature exists to prevent, reintroduced by the prefill meant to save
typing.

**It sits last, it is drawn small, and it moved the form to two sections.** The
cursor starting in the amount was a first-feedback-batch decision and the right
one, so nothing goes above it, and this is the least often touched of the four
rows under it. It is a `qualifier` — the same step down the type scale as Tip,
Currency and the rate — with `.controlSize(.small)` beside the font, because a
compact `DatePicker`'s label follows `.font` and its date pill does not, so the
step down applied to half a row reads as a mistake rather than a decision.

Title and Amount are now a headerless section of their own, and Tip, Currency,
rate and Date are **Expense Details** below them, which is where Categories will
land. The two mechanisms do different jobs: the type scale says *how much these
matter*, the section boundary says *what they are* — a group to skip in one
glance rather than four rows you must read to discover are optional.

**The details section is deliberately not collapsed**, which was the obvious
next step and is the wrong one. Three things in it have to stay visible. The
exchange rate is *required* once a foreign currency is picked — and a currency
prefills from the last one used, so mid-trip it can already be foreign on a form
nobody has opened; behind a chevron that greys out Save with the explanation
folded away. `savesAsSummary` is the only place a mis-parsed separator or an
upside-down rate is catchable before saving. And the date's whole value is that
somebody adopting the app on day three of a trip can *see* that days one and two
are enterable — hiding it takes back the reason the row was added. Revisit when
Categories makes it five rows, and only under the rule that the section is open
whenever anything inside it is non-default.

That widened what `qualifier` means, and the widening is the part worth keeping.
Its rule was *qualifies the amount rather than being it*, which is true of the
first three and made the date look like an exception, since a date is a property
of the expense the way the title is rather than an adjustment to its figure.
Drawn full weight on that reasoning, it was wrong on screen. What the four rows
actually share is that they are **prefilled and optional**: the form opens with
an answer already in each, and in the ordinary case — a single-currency group
buying a round today with no service charge — not one is touched. A required
field and a defaulted one should not carry the same weight, and the settle-up
sheet takes the same step down for the same reason. `.compact` shows the real
date rather than a *Today* placeholder, so the capability stays visible without
being in the way.

**Settling up got the same field**, in the sheet **Settle part of a debt** had
just added — *"I paid her back last Tuesday"* is the same sentence, and a
payment stamped today lands in the wrong day of the same log. **Mark Paid** is
untouched and still stamps now: it has no form to ask with and has to stay one
tap, and anybody settling on a different day is already opening the sheet.

*Cost: unmeasured. Two `DatePicker`s, three defaulted parameters, and one string
in both languages. No model change and no CloudKit promote.*

### Categories

**Asked for by mail on 2026-08-31**, the first time this entry had a request
behind it rather than an author's hunch, and paired in the same message with
**Choose the date on an expense**. Neither is about getting a number into the
app faster; both are about the log being readable weeks later. The date half
needed no model change and shipped first for that reason.

An optional `symbolName` on `Expense`, the same trick the group's own icon
uses, so a full set of twelve costs one optional String and nothing in the
bundle. Nothing in `SettlementBridge` reads it — an expense filed under
*Groceries* splits exactly as an unfiled one does, which is what lets an older
client that has never heard of categories keep computing identical balances.

**Twelve fixed cases, not free text.** Freeform names need a search field and an
empty state, and two people in the same group would file the same dinner under
"Food" and "food" and never see each other's.

**A menu, not the symbol grid.** A group's symbol is decoration chosen by eye,
so `AppearancePicker` shows glyphs alone; a category has a *name*, and twelve
glyphs with no words under them would ask whether the bolt means electricity or
speed — the exact ambiguity a category exists to remove. The row draws the glyph
only, because the log is scanned rather than read and the menu is where the
glyph is learned. Nothing at all is drawn for an unfiled expense: a placeholder
tag would make "no category" look like a category, which most expenses will be.

**`None` is a real choice.** `apply` writes the category on both paths, `nil`
included, so clearing one actually clears it — an attribute only ever
overwritten with a non-nil value is one the user cannot take back. A duplicate
carries the category over, unlike the date: four people taking turns at the bar
are filing four *Drinks*, and that is exactly the retyping Duplicate exists to
save.

**The glyph on the row was too quiet, and the field did no work.** Both were
reported by the first person to use categories on real expenses — *"we can
select a category but can't see it anywhere"* — and they are two failures, not
one. The row glyph was `.caption`/`.secondary`, drawn on the reasoning that the
log is scanned and the picker is where glyphs are learned; in practice it was
invisible. It is level with the title it sits beside now.

The second failure was the real one: an expense could be filed and nothing ever
read the filing. So the summary section grew a **breakdown** — spend per
category, biggest first, uncategorised always last however large, with a bar
per row. Uncategorised sorts last because it is the absence of an answer rather
than one of the answers, and heading the list with it would make the first line
the one that says nothing. Hidden entirely until something has been
categorised, since a group nobody files gets one bar equal to the total two
lines above it.

It is computed in `Contents`, in the pass that already walks the log — a
breakdown recomputed in the section's body would re-walk it on every redraw, and
this screen redraws on every tap. Reimbursements are excluded exactly as they
are from Total Spent: counting a settle-up would attribute the same money twice.

**The ordering lives in DutchKit, and moving it there found a bug.** It began as
a `sorted(by:)` inside a view body, which is untestable — `Contents` is private
to `GroupDetailView`. `SpendBreakdown.slices(of:)` is generic over the bucket,
so it needs nothing the app knows, and the nine tests on it pin the rules that
were previously only assertions in a comment. The bug: `sorted(by:)` is **not
stable in Swift**, and the original comparator returned `lhs.total > rhs.total`
with no tie-break — two categories coming to the same figure could swap places
between one redraw and the next, on a screen that redraws on every tap. Ties now
break on the key. The zero-total guard moved with it, so `0/0` producing a `nan`
fraction that draws as nothing is covered by a test rather than by a ternary at
the call site.

The bar is the group's own tint, not a colour per category. Twelve categories
would need twelve colours, the palette has eight and deliberately excludes the
two the balances spend, and a chart that reuses its colours every eight rows
tells the reader nothing.

*Cost: 34 KB archived for the breakdown and the two fixes together — see the
size note under **Archive a group**. One attribute, twelve cases, fifteen
strings in both languages.*

### Member avatars from SF Symbols

An optional `symbolName` on `Person`, drawn *instead of* their initials. The
symbols ship with the OS, so this costs one optional String and nothing in the
bundle — where photo avatars would have meant a picker, a downscaler, a
`CKAsset` per member through a shared zone, and a reason to ask for the photo
library.

**Nobody gets one by default, and that is the feature working.** `PersonAvatar`
still derives initials from the name that is already there and a colour from the
id that is already there; the glyph is an override on top. A roster of identical
`person.fill` circles would be worse than what it replaced.

**Forty-eight symbols, and the count is close to free.** Twenty-four was the
number a group needed; a member picking a personal emblem wants more range.
Measured 2026-08-31, going to forty-eight cost **1,549 bytes** — 32 of them in
the binary, the rest in the two `.strings` files. The archive did not move at
block granularity. The glyphs ship with the OS, so the price of a symbol is its
*name in two languages* and nothing else, which is worth knowing before anyone
argues about the list on size grounds again. Every case existed by iOS 16,
comfortably under the iOS 17 floor: a name the running OS has never heard of
renders as nothing at all, so the list rules that out by construction rather
than catching it at runtime.

**The group's set is now shared rather than copied.** `GroupSymbol` became
`Emblem`, for the reason `PaletteColorGrid` is one grid: two curated lists drift
into different glyphs, different translations and different iOS floors while
both claiming to be "the symbols you can pick". It is named for neither owner
because it belongs to both — a `Person` whose emblem was typed `GroupSymbol`
would read as a bug every time anybody opened the file. The raw values did not
change, so nothing already stored moved. Sharing it also kept the string cost at
one new key: *Initials*, the way back out.

**A member's grid offers that way back; a group's does not.** A group always has
a symbol. `EmblemGrid` takes an optional binding and an `includesNone` flag, and
`AppearancePicker` bridges its non-optional one through it.

*Cost: unmeasured. One attribute, one renamed type, one new string.*

### Archive a group

Trips end and the list never shrank. One optional `archivedDate` on
`ExpenseGroup`, a leading swipe, and a collapsed disclosure holding whatever has
been put away.

**A `Date`, not a `Bool`, for something this build does not use.** *When* a trip
ended is the sort key an archive screen would eventually want, and a boolean
cannot be widened into one later without a second model version and a second
CloudKit promote. The attribute costs the same either way; this is the cheap
half of a decision whose expensive half is irreversible.

**It syncs.** Archiving is a statement about the trip rather than a preference
of whoever is looking — the dinner is over for all six people — and a flag that
moved on one phone only would leave the same group in two states with nothing to
say which is right. Anyone can undo it, which is the contract renaming already
has.

**Archived groups still count against the free limit.** The rule is on groups
*created*, and archiving changes a list rather than what was created.
Discounting them would also make the limit bypassable by archiving, creating and
unarchiving — the kind of hole found within a week of shipping. So
`GroupListView` fetches **unfiltered** and splits for display only, and
`GroupLimit.createdCount` keeps seeing everything.
`archivedGroupsStillCount` is the guard, and the note is on the function rather
than here because that is where somebody would otherwise "optimise" the fetch.

**A disclosure, not a second screen.** The navigation path is typed
`[ExpenseGroup]`, so a separate archive destination would mean widening it to an
enum and rewriting every push for a list most people open once. Collapsed on
every launch, and absent entirely until something is in it — a permanent
*Archived (0)* is a row explaining a feature nobody has used.

**The swipe was not enough, and that was predictable.** Shipped as a leading
swipe and nothing else, the first question back was *"how do I archive a
group?"* — which is the failure `TransferRow` already carries a comment about: a
gesture with no affordance is a feature most people never find. It is in the
**Edit Group** sheet now, which is where somebody finishing with a trip looks,
and the swipe stays as the fast path for anyone who knows it is there. Not
drawn `.destructive`: archiving destroys nothing and one tap in the same place
undoes it, so red would read as the delete this deliberately is not. Archiving
from the sheet leaves the screen open, because popping back to the list would
itself read as a delete.

**On the leading edge, opposite Delete.** Archiving is the *un*-destructive half
of "I am finished with this trip", and putting it under the same thumb sweep as
the action that destroys every expense in the group is how a swipe becomes
something people stop doing. The two `onDelete` handlers now index their own
section's array rather than the fetch, which is the bug two sections over one
`FetchedResults` would otherwise have introduced silently.

*Cost: one attribute, one store method, five strings.*

*Measured for all three of Dutch 7 plus the category breakdown, 2026-08-31:
**1,752 KB → 1,780 KB** archived, the last 20 KB being the archive control in
the Edit Group sheet and the breakdown's move into DutchKit. The code added 34 KB and
`ASSETCATALOG_COMPILER_STANDALONE_ICON_BEHAVIOR = none` gave 28 KB back, so the
net is +8 KB — the icon saving paid for the breakdown and very little else.
288 KB of the 2 MB ceiling remains.*

---

## Next

### 8. Home screen widget

"You owe €120 · green-moon-tea". A WidgetKit extension reading the same store.
Depends on knowing who you are, above. A couple hundred KB for the extension binary.

The awkward part is already done: both the Core Data stores and `ExpenseDefaults`
live in `group.net.smigi.Dutch`, so the extension can open them. That was the one
piece of this that would have been expensive to retrofit — moving a store after
people have data in it abandons whatever hadn't synced.

### 12. Exact amounts in a split

Not another way of dividing a bill — the same division, entered differently.
Percentages ask *in what proportion*; this asks *how much exactly*, because
sometimes the receipt already says.

**The one situation it is for:** one person pays the whole bill, and the bill is
itemised. Three people, one card, 127.00 paid:

| | on the receipt |
|---|---|
| Ania — salad | 23.50 |
| Marek — steak | 68.00 |
| Kuba — pasta | 35.50 |

The numbers are already known. Getting there with percentages means computing
18.5% / 53.5% / 28% first, which is exactly the arithmetic this app exists to
delete. Today the workaround is three separate expenses, each paid by the card
holder and split among one person: it works and it is correct, but it is three
trips through the form and the group then reads "3 expenses" for one dinner.

**Where it does *not* apply:** if everybody paid for their own meal, nothing
needs entering at all. One person covering someone else — Marcin paying for
Kasia because she had no cash — is already an ordinary expense paid by Marcin
and split among Kasia alone. Rounds at the bar are one even-split expense each.
None of that needs this feature; the friction rounds actually had is what
**Duplicate an expense** above fixed.

**Mixed is the real shape of it.** "Ania pays her 23.50, the rest of us split
what's left" means some rows are fixed and the remainder divides between the
others by percentage. So a row is either an amount or a percentage, the fixed
ones come off the top, and what remains is divided among the rest.

That is what makes it the hardest control in the app, and why it stays separate
from the percentage menu rather than sharing a field with it — `50` cannot mean
half a share on one row and fifty złoty on the next. It also breaks the one
invariant everything else here relies on, that the parts reconstruct the whole:
this needs a running remainder on screen at all times, and a decided answer for
what happens when the fixed amounts overshoot the total.

Asked for directly, twice, in the first week of feedback.

**The model change this entry demanded turned out not to be needed.** The line
above used to read "do it in the same model version as **16**", which held this
behind two features it does not depend on. `Money.split(among:)` allocates
`cents * weight / total`, so weights that *are* the cents and sum to the whole
come back exactly, with no remainder left to redistribute — and `ExpenseEntry`
already documents that weights are relative and that nothing depends on reading
them as percentages. `DutchKit/ExactSplit` does that conversion; the storage is
the `shareWeightsJSON` string that has been there since percentages shipped.

The consequence is better than the no-op it looks like: a client too old to know
about this decodes the same integers and computes the *same cents*. The
percentage weighting shipped without that property — a client predating the
attribute fell back to an even split.

Which rows were typed as cash rather than derived is a presentation detail, and
rides in the same JSON under `$exact.<uuid>` keys. `shareWeights` already
discards any key failing `UUID(uuidString:)`, so those are invisible to every
build that has ever shipped. Nothing about the split depends on them; losing
them entirely would cost a nicer edit screen and not one cent.

**What was decided, since the entry asked for both.** The remainder sits in the
split section's footer and displaces the standing percentage explanation once a
figure has been typed — it is the sentence that changes as you work. An
overshoot, and a shortfall with nobody left to absorb it, both block Save with
the figure named, following `PartialPaymentSheet` rather than clamping silently.

Exact figures are lines off a receipt, so they are read in the currency being
typed in and *before* the tip — the same field they sit under. Because the
weighting is relative, a tip and a conversion then apply themselves
proportionally: everybody pays their own item, converted, plus their share of
the tip. The one thing that does not survive a round trip is the tip's
separateness: reopening shows each person's item with their share of the tip
already folded in, because that is what they owe. The money is right; the
itemisation is one step less granular than it was when typed.

### 16. Several people paid

`paidBy` is a to-one relationship in the model *and* `payer: Participant.ID` in
`SettlementCalculator`, so this reaches all the way down: a model version, a
CloudKit promote, and a change to the one contract every balance in the app is
computed through.

It is also the symmetric end state. An expense today has one payer and many
sharers; there is no principled reason the paying side is the singular one, and
"we split the taxi and two of us put money in" is an ordinary sentence.

What held it back was that the workaround is not a workaround — it is exactly
correct. Two expenses, one per payer, produce identical balances.

**That turned out to be the reason to build it, not to skip it.** If two records
are exactly right, the app writes the two records and the form stops being a
place you visit twice. `GroupStore.addExpenses` decomposes at entry and nothing
downstream changes: `paidBy` is still to-one, `ExpenseEntry.payer` is still
`Participant.ID`, and `SettlementCalculator` — "the one contract every balance
in the app is computed through", which this entry named as the risk — was not
touched.

The decisive argument is one this entry missed. Payer information stored
anywhere *new* is invisible to a build that predates it, **a new Core Data
attribute included**. Under the to-many plan a member who hasn't updated credits
the whole amount to one person and quietly computes different balances from
everybody else in the group — the one failure this app cannot take. Decomposed,
there is nothing new to miss: every build at every version sees the same two
ordinary expenses.

`ExactSplit` from **12** does the arithmetic unchanged; contributions are fixed
figures against the tipped total, and a payer left blank takes an equal part of
what the others don't cover. It is the same control on the other side of the
bill, exactly as this entry predicted — it just turned out that **12** had
already paid for it.

**Available on an edit too, and deliberately behind a toggle.** This was
add-only at first, on the reasoning that an edit rewrites one record and has
nowhere to put a second payer without silently creating a row. Two things
answered that: the row is not silent — the footer names it before Save — and it
can be dated correctly, which is only true because **Choose the date on an
expense** shipped first. Without that field, a payer added to last Tuesday's
taxi would have landed in today's bucket.

Editing is also where the need actually arises. The taxi is already in the log
when somebody remembers they chipped in, and the alternative was deleting the
expense and entering two — on a shared group, precisely the delete-and-re-add
churn that **Edit an expense** exists to prevent. The edited record keeps its
identity and shrinks to its payer's part; the others arrive as new rows on the
same date.

The sibling records are not linked, so an edit only ever describes how *this*
record divides. Reopening it afterwards shows one payer and the reduced figure,
with the other row standing on its own in the log. That is the honest reading of
a model with no multi-payer expense in it, and it is the trade that keeps this
free of the grouping marker.

The toggle is the more easily lost decision. Multi-select-by-default made
*correcting* the payer — far and away the commoner action — cost two taps: pick
the right person, then unpick the wrong one. So a tap replaces, as it always
did, and **Several people paid** at the foot of the section is what changes what
the rows mean. That is the same shape as `Uneven split` one section below, on
the principle that a rare mode must never tax the tap everybody makes.

**What it does not buy is the tidiness this entry led with.** Two people paying
for one taxi is still two rows in the log. The saving is the typing — one pass
through the form instead of an add, a Duplicate and two corrections, at a taxi
rank. If a single collapsed row is ever the actual request, that is a different
feature and it needs the grouping marker this one deliberately avoids.

One artifact worth knowing: splitting 50 once is not bit-identical to splitting
30 and 20 separately, because each record rounds independently. Every record
sums exactly and every device agrees, so the group always reconciles — an
individual's share can just sit a minor unit from what a single record would
have given them.

---

## Waiting on a decision, not on space

These four were raised together, with the reasonable assumption that the size
ceiling rules them out. Measured, it doesn't. Three of them cost approximately
nothing in the bundle — CoreLocation and MapKit ship with the OS, and the
country-to-currency mapping is already sitting in Foundation. The fourth costs
432 KB, inside a budget with well over a megabyte of headroom.

What actually gates them is a permission prompt, a network round trip, a model
version and some layout work. So they are here rather than in **Next**, and none
of the decisions is about bytes. The first three turned out not to be three
decisions either — they share a single tap, and are written up below as one
batch rather than as three entries that would each have to answer the same
permission question separately.

### 19–21. Nearby: one tap, three consequences

**Written on 2026-09-04, and half-promoted.** All three are implemented and
running on a device. `Dutch 8` (`CD_placeName`) was initialized and promoted the
same day; **`Dutch 9` — `CD_latitude` and `CD_longitude` — has had neither**, and
until it does, any TestFlight or App Store build that attaches a place will fail
mirroring outright. The order is in *Dutch 9, and the order it has to happen in*
below, and the two-build check under *Fallback for peers on an older build* is
still outstanding.

These three were written up separately, and the separation was the mistake.
They are not three features with three permission stories and three switches.
They are **one tap — Nearby — with three consequences**, and the tap is the
consent event that makes all three acceptable:

- **19** is the tap: the cafés and restaurants within a hundred metres, one of
  them chosen, its name in the title.
- **20** rides on the *result* of that tap, not on a second reading of the
  user's location.
- **21** is what is kept from the same result.

So there is one location service, one permission prompt, one Settings section,
and a user who never taps **Nearby** never has a location read, never has a
currency changed under them, and never syncs a place to anybody.

#### 19. The Nearby button

Asked for as: an empty title becomes the current location, and better still, a
picker of the establishments nearby.

That is two features wearing one coat, and only one of them is worth building.
Reverse-geocoding to *Kraków* and dropping it in the title is close to
worthless — the group is already called *Kraków Trip*, and every expense in it
would carry the same word. The valuable half is the second one: the cafés and
restaurants within a hundred metres, one tap, and the title reads *Café Camelot*.
MapKit is system, so it costs nothing in the bundle.

**Reverse-geocoding came back as a fallback, and only as one** — added
2026-09-04, after the first run on a real phone answered *Nothing Nearby* from
an ordinary desk. The rejection above still stands for what was rejected: the
*town* is worthless in a group named after it. A **street** is not. It is the
one thing that separates the market stall, the taxi and the beach bar that Maps
has never heard of, and those are precisely the expenses that reach an empty
search. So an empty result reverse-geocodes once and offers a single row, the
sheet says in a footer why it is showing a street, and the row still has to be
tapped. It also puts the currency prefill back on that path, since a placemark
carries `isoCountryCode` exactly as a map item does.

Two things about it are deliberate. It never runs first, because a real place
beats an address every time. And a street is a **sharper** fact than a café
name — *Café Camelot* is a public place, *Długa 5* can be somebody's flat — so
it stays behind the same explicit tap and out of the title until one is made.

**The API is `MKLocalPointsOfInterestRequest(center:radius:)`, not
`MKLocalSearch.Request`.** The latter searches for text and needs a query
string; this one browses what is there, takes an `MKPointOfInterestFilter`, and
is passed to `MKLocalSearch` the same way. Getting this wrong means inventing a
query — *"restaurant"* — and getting the results for places with that word in
the name.

Three things stand in front of it:

- **The permission prompt arrives at the worst possible moment.** The first
  expense is entered at the table, and the app's whole pitch is that nobody has
  to do anything before the coffee gets cold. The same trade was already
  refused under **Tip, tax and service charge** above — scanning a receipt
  total is not worth a camera prompt.
  This one buys more than that one did, because a name is more typing than a
  number, but it needs the same care: the prompt has to sit behind an explicit
  **Nearby** button that the user taps, never behind the form appearing.
- **`MKLocalSearch` is a network call**, and the trip abroad is precisely where
  roaming is off. It has to degrade to the plain text field that is there today,
  quietly, without an error the user can do nothing about. The trap found in
  practice is the opposite one: MapKit reports *no results* by **throwing**
  `MKError.placemarkNotFound`, so a first version that caught every throw as a
  network failure told everyone on a quiet street that Apple Maps was
  unreachable, and made its own empty state unreachable too.
- **The title is deliberately optional** (the reasoning is in `ExpenseFormView`).
  Filling it in automatically whenever it is left empty reintroduces exactly
  what that decision removed: a field the user now has to stop and check.

So the shape is a **Nearby button, not a prefill** — which resolves the first
objection and the third at once.

**The title is filled only when it is empty**, decided 2026-09-04 after the
first version overwrote it outright. That version's reasoning was that a tap
plus a row chosen is two explicit answers to "what is this called", and it was
fine as far as it went; what it lost was the person who typed *Anna's birthday*,
then attached the café, and watched their sentence replaced by a shop sign.
Typing is the more specific of the two answers and the one that cost effort.
Nothing is lost by leaving a written title alone, because the place attaches
either way and the row in the form is what records it.

The service is `ExpenseNotifier` again, in a different framework. That type is
the codebase's worked example of a permission-gated feature: `@MainActor`,
`ObservableObject`, a published `authorization`, an `enable()` that can come back
refused, and a `SettingsView` toggle mirrored in `@State` so a refusal doesn't
leave a switch sitting on above a feature that cannot fire — plus the
`openSettingsURLString` link for `.denied`, which is the only route back after
iOS has asked once. Copy that shape rather than inventing a second one.

Prefer an explicit `CLLocationManager` — `requestWhenInUseAuthorization()`, then
a one-shot `requestLocation()` — over the iOS 17 `CLLocationUpdate` sequence.
Not because the newer API is worse, but because the prompt has to be a step the
button owns, so the button can show what happened when the answer was no.

*Cost: zero bytes; MapKit and CoreLocation are system. One
`INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` — a scalar key, so unlike
`UIBackgroundModes` it can live in a build setting — one button and one sheet.
No model change.*

#### 20. The currency, from the country the chosen place is in

The cheapest of the three, and the one whose payoff is clearest. The app already
thinks about the traveller: `ExpenseDefaults` keeps the last currency per group
and the last rate per group *per currency*, precisely so a trip through three
countries doesn't overwrite one rate with the next.

**The mapping needs no table.** `Locale(identifier: "und_PL").currency?.identifier`
returns `PLN`, out of the ICU data already in the OS — verified for PL, NL, JP,
GB, CH, HU and CZ. That matters because an embedded currency database is one of
the four things named at the top of this file as an actual size risk, and this
isn't one. It is also Foundation-only and testable without a simulator, so by
the rule in `CLAUDE.md` it belongs in **DutchKit**, with those seven cases and
the `nil` one for a region ICU has no currency for.

What it needs is the country, and this entry used to name two places to get it
and reject both: `Locale.current.region` is the device's *region setting*, not
where the device is, which is wrong for exactly the person this feature is for;
and CoreLocation means a permission prompt for a prefill.

**There is a third, and it is free.** The `MKMapItem` the user picked in **19**
carries `placemark.isoCountryCode`. No `CLGeocoder`, no second network round
trip — reverse geocoding is both, and rate-limited besides — and no second
consent question, because the country comes from a place the user chose out
loud. If they didn't tap **Nearby**, there is nothing to prefill from, which is
the honest answer rather than a missing feature.

**The trap is the rate, not the currency**, and the code already handles it:
`onChange(of: currencyCode)` in `ExpenseFormView` replaces `rateText` with
whatever `ExpenseDefaults.lastRate` holds for the new code, and leaves it empty
when there isn't one. So the automatic switch must set `currencyCode` and *let
that handler run*. Anything that assigns the rate itself reintroduces precisely
the bug: the first expense in a new country converted at the last country's
rate, which is wrong and looks entirely plausible.

The other guard is `isEditing`. Reopening an expense saved in Budapest must
never rewrite the currency it was saved in because the phone is now in Kraków.

*Cost: zero bytes. A `UserDefaults` key, a `Toggle`, and a small `Sendable` type
in DutchKit. No model change.*

#### 21. The place on the expense

The name that was chosen, stored on the `Expense`, so that "how much did we
spend at which place" can be answered later.

**Three attributes after all — `placeName` in `Dutch 8`, then `latitude` and
`longitude` in `Dutch 9`** — but not for the reason this entry originally gave,
and it is worth being exact about which argument survived.

The original pairing advice is void: **12 and 16 shipped without touching the
schema.** Exact amounts became cent weights in the weighting that already
existed; several payers became several ordinary `Expense` rows, decomposed at
entry in `GroupStore`. There was no version to share.

So `Dutch 8` shipped as name-only, on the argument that **a field promoted to
the Production CloudKit schema can never be removed** and nothing in the app had
a use for coordinates — the overview they would serve being a charts screen,
which is in **Not planned** below.

**That was overturned on 2026-09-04 by a use the argument had not considered:
opening the place on a map.** Not an overview of anything, and not a screen —
one tap on the row already in the form, landing on the pin in Apple Maps. That
is the answer to "where was this", asked about a single expense, by somebody
looking at it; and it cannot be done from a name. A name search opens whichever
branch of the chain is nearest *now*, which on a trip home from Kraków is the
wrong city.

The costs were taken deliberately and both stand:

- **A second promote**, three weeks of runtime after the first if it comes to
  that. Cheap, mechanical, and written down below.
- **The permanence.** `CD_latitude` and `CD_longitude` are in the Production
  schema forever now. That is the real price, and it was paid for a feature
  somebody asked for rather than for one that might be wanted later — which is
  the distinction the original argument was actually reaching for, and stated
  badly as "nothing has a use for coordinates".

What did **not** change is the privacy shape: still per expense, still only as
the consequence of a tap on a row the user chose, still removable, and still no
background location. A coordinate is a sharper fact than a name and the privacy
pages say so plainly rather than eliding it.

The privacy question survives the trim and is easier to answer for a name than
for a coordinate pair: **a place on a shared expense is a place shared with the
group, permanently.** Everything the app syncs today is who, what, how much and
when; *where* is a different category of fact about a person, it goes into the
shared zone, and it does not come back out. That makes it acceptable only as a
consequence of the tap in **19** — per expense, visible at the moment it is
attached, never automatic and never collected in the background.

On the privacy page: nothing here becomes collected data, because there is still
no server and no analytics, and CoreLocation is not a required-reason API, so no
`PrivacyInfo.xcprivacy` appears in a tree that has none today. What does need a
line is the App Store nutrition label and `website/privacy/`. The README's *no
trackers* stays true only so long as this remains opt-in and stays out of any
background location mode.

*Cost: zero bytes. Three optional attributes across two model versions, and two
CloudKit initialize-and-promotes — the second of which is outstanding.*

#### Dutch 9, and the order it has to happen in

The order is the reverse of the one that feels natural, and this is the step
that gets missed. It was done once for `Dutch 8` and is **outstanding for
`Dutch 9`**:

1. Add the model version — `Dutch 9.xcdatamodel`, `latitude` and `longitude`
   optional and non-scalar — and bump `.xccurrentversion`.
2. Run once in Xcode signed in to iCloud with `-initialize-cloudkit-schema`.
   Skipping this on the theory that mirroring creates fields lazily is the
   documented trap: it does, but only as records populating them actually sync,
   so the console reports "0 changes to deploy" and everything looks fine.
3. **Promote to Production, then ship.** The schema is server-side, so it can
   land before the binary does. Shipping first produces
   `Cannot create or modify field 'CD_latitude' in record 'CD_Expense' in
   production schema`, which aborts mirroring entirely and takes sharing down
   with it — a bug visible only in a distributed build.

**Non-scalar, and that is not a formatting preference.** A scalar `Double`
attribute defaults to `0.0`, and 0,0 is a real point in the Gulf of Guinea —
every placeless expense in the app would sit on the same island, and no reader
could tell "no coordinate" from "somebody was there". `NSNumber?` makes absent
mean absent.

#### Fallback for peers on an older build

Three cases, and only the third is genuinely open:

- **Old store, new app.** Lightweight migration, attribute optional, existing
  rows read unchanged. This is what the model versioning already covers.
- **Old app, new record arriving over CloudKit.** The Production schema is
  additive; a Dutch 7 client's mirroring ignores `CD_placeName` and shows the
  expense without a place. The degradation is invisible in the right way — no
  empty row, no placeholder, nothing to explain.
- **Old app *editing* that expense.** Mirroring exports the properties that
  changed, so the unknown field ought to survive — but "ought to" is doing the
  work in that sentence, and the failure would be a friend who hasn't updated
  silently erasing a place. Two builds side by side on one shared group, one on
  Dutch 7, is a ten-minute check and the only way to know. **Do it before the
  promote, not after.**

Downgrading — a Dutch 8 store opened by a Dutch 7 binary — hits the `fatalError`
in `loadPersistentStores`. That is a TestFlight-rollback concern rather than an
App Store one, but it is worth knowing before rolling one back.

#### Settings, and what defaults to off

One **Location** section, below **Launch**, two switches, both off by default —
`store.bool(forKey:)` on a never-written key gives that for free, the same way
`reopenLastGroup` does:

- **Nearby Places.** Gates the button existing at all, and with it everything in
  **19** and **21**.
- **Currency from Location.** `.disabled` unless the first is on. Separate,
  because wanting the name is not the same as wanting the currency changed
  underneath you, and **20** is the one of the three that acts without being
  asked a second time.

The two keys live in different places, and the split follows the one that
already exists: **Currency from Location** is an `ExpenseDefaults` key bound by
`@AppStorage`, exactly like `reopenLastGroupKey`, because the switch's position
*is* the setting. **Nearby Places** is owned by `NearbyPlaces` and mirrored into
`@State`, exactly like `ExpenseNotifier`'s, because turning it on ends in a
system prompt that can say no and a switch bound to the answer would flick on
and visibly back off. Both write to the app-group suite.

#### Sequencing

Three commits on one branch, each shippable alone:

1. The location service, the Settings section, and the permission string.
   **Nearby** fills the title. That is **19**, complete, with no schema and no
   CloudKit anywhere near it.
2. The currency from the picked place's `isoCountryCode`, plus the DutchKit type
   and its tests. That is **20**, pure form logic.
3. Dutch 8, `placeName`, and showing the place on the row; then Dutch 9 and the
   coordinates behind the Maps link. That is **21**, and it is the only one
   carrying the initialize-and-promote — twice.

   Written as a label rather than as grouping, which this entry originally
   called for. A pick writes the title *and* the place, so on the ordinary row
   the two are the same string and the *words* are not repeated — the place
   appears on the payer's line only once somebody renames the expense. A pin
   glyph beside the title marks the attachment in every case, added after the
   first version left an attached place with no trace on the row at all: for
   something that syncs to the whole group, "open the form and look" is the
   wrong way to find out it is there.

   Grouping needs a second answer first: the log is already grouped by day, and
   a second axis over the same list is a control, not an attribute. Left open
   deliberately.

Two mechanical notes that are easy to lose, both from the **Localization**
section below:

- `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` has to be set on **both**
  build configurations, and the English source mirrored into
  `InfoPlist.xcstrings` with a Polish translation — exactly as
  `NSCameraUsageDescription` already is. The build setting alone ships an
  untranslated prompt.
- `xcodebuild build` does not sync the string catalog. New literals need the
  Xcode IDE or `-exportLocalizations`, or they silently never become keys.

And measure the result by archiving, not building. MapKit and CoreLocation ship
with the OS; what this batch costs is its own code, against the 1644 KB the top
of this file records.

### 22. iPad and Mac

The only one of the four with a real number attached to it, and the number is
**432 KB**.

`TARGETED_DEVICE_FAMILY = 1` is in the savings table at the top of this file,
and what it saved was the asset catalog storing a second copy of every icon
rendition for the `pad` idiom. Supporting iPad puts them back.

That was worth measuring rather than estimating, and the measurement moved the
answer. Against the 1644 KB archived on 2026-08-28 it lands at **2076 KB** —
comfortably inside the 3 MB constraint, and about 28 KB *over* the 2 MB the
README advertises. On the 1552 KB of 2026-08-20 it would have fitted with room
to spare; Polish spent that room.

So iPad is not blocked, but it is no longer free of a decision: **the thing that
changes is the README's line, not the feature.** 2 MB is a claim this project
made about itself, 3 MB is the constraint at the top of this file, and the honest
options are to drop the claim to "under 3 MB", find 28 KB elsewhere, or decide
iPad layout isn't worth the sentence. Worth knowing that the 432 KB is pure
duplication — the same renditions stored twice under two idioms — so a smarter
catalog, not a smaller app, is where that money would come back from.

Worth being clear about what the bytes buy, which is nothing. Dutch is not
unavailable on iPad today; it installs and runs in iPhone compatibility mode.
This is a *layout* feature — a `NavigationSplitView`, a form that doesn't
stretch a text field across eleven inches — and the honest question is whether
that layout work is worth 432 KB, not whether iPad users can run the app.

**The Mac is nearly free once iPad is done, by one route and not the others.**
"Designed for iPad" is a checkbox in App Store Connect on Apple Silicon: no
target, no code, and not a byte in the iOS download. Mac Catalyst and a native
macOS target are both genuine work, and both ship a separate binary whose size
never counts against the iOS download at all — so even there, size is not what
decides it.

Sync is the part that already works: CloudKit is per Apple Account, so the same
private database and the same shared zones simply appear. Two things would bite
if this ever goes past the checkbox:

- **The app group identifier is spelled differently on macOS** —
  `$(TeamIdentifierPrefix)group.net.smigi.Dutch` under Catalyst. Both persistent
  stores and `ExpenseDefaults` live in that container, and both deliberately
  fall back to the old location when the entitlement is missing. So getting it
  wrong doesn't crash: it silently opens an empty database on the Mac and reads
  as a sync failure.
- **Share acceptance lives on the scene delegate**, and the AppKit path is a
  different method again. The failure mode is the one this app has already had
  once — invitations that appear to do nothing.

*Cost: 432 KB for iPad, being the reverse of a saving already taken and already
measured. Zero on top of that for "Designed for iPad". No model change.*

---

## Wanted, and the first one that costs real space

The section above exists because four features were assumed to be gated by the
size budget and measured not to be. This one is why that heading is worth
keeping: it is the first request on this page whose honest answer is *yes, and
it is the largest thing here in bytes.*

### 24. An iMessage app

Asked for as: assign a group to a group chat, and manage its expenses without
leaving Messages — which is where the conversation about the dinner already is.

**It is a target in this project, not a second app.** A Messages extension ships
inside the app bundle, on the same submission, under the same bundle ID; there
is no separate listing and no second product to maintain. (Apple also allows a
standalone Messages-only app with no host at all. That exists for sticker packs
and is not this.) Checked on 2026-08-29, because the framework's future is a
reasonable thing to doubt: nothing is deprecated and `MSMessagesAppViewController`
is current. What has happened is de-emphasis — the app drawer moved behind the
"+" button — so *still supported* is settled and *still findable* is not.

**Two expensive things are already paid for**, both bought for the widget and
both serving this unchanged. Both persistent stores and `ExpenseDefaults` live
in `group.net.smigi.Dutch`, which is the retrofit that would have cost real data
to do later. And `Intents/` was kept self-contained on the stated grounds that
it is the part a second front end reuses verbatim — this is that second front
end. `IntentWriter` already holds the policy for recording an expense with no
form to apply it, and `GroupLookup` already fetches a group imperatively for a
caller with no view to hang a `@FetchRequest` on. Both are precisely what a
Messages UI needs.

**The first experiment decides whether the feature exists**, and it is not a UI
question. `NSPersistentCloudKitContainer` exports off persistent history. If the
extension writes through a plain container, the export may not happen until the
host app next launches — an expense added from Messages would sit invisible to
the rest of the group until somebody opened Dutch, which is the one outcome this
feature cannot have. Giving the extension a mirroring container of its own is
the alternative, and means two of them over one store. Which holds is not
guessable from the API surface and has to be measured on two devices, before any
of the UI. Note its shape: it fails silently and it reads as a CloudKit problem,
which is the same trap as the `UIBackgroundModes` key.

**A chat maps to a group on this device only.** `MSConversation` offers
`remoteParticipantIdentifiers` and `localParticipantIdentifier`, opaque UUIDs
scoped to one app on one device and explicitly not identities — so no roster can
be built from the chat and no participant matched to a `Person`. Nothing here
needs that. *This chat is green-moon-tea* is a fact about the device, which is
where `ExpenseDefaults` already keeps who you are and which group you last
opened. That the mapping doesn't follow you to another device costs nothing in
an iPhone-only app.

**It may be worth more as a way in than as a way to spend.** A join QR scanned
by somebody without Dutch installed is a dead end — Apple's page offers no route
to the App Store, which is the whole reason `ShareGroupView` carries a second
collapsed App Store code. An `MSMessage` bubble is Apple's own answer to that
case: sent to someone who doesn't have the app, the bubble offers it. And
sending an invitation into the group chat is the remote-case equivalent of
holding a QR code up at the table, which is exactly the case the QR structurally
cannot serve. It wants confirming on a current OS before it is relied on, but it
closes a gap rather than saving taps.

**What it costs is a second binary.** An extension is its own Mach-O with its
own view code and its own copy of DutchKit; it cannot share the app's. The app
is 1644 KB, this page already calls 2 MB close-run, and the widget is budgeted
at a couple hundred KB on top of that. The two extensions together plausibly
take Dutch past 2 MB for the first time. That is well inside the 3 MB ceiling,
so it is a trade rather than a refusal — but it is the largest single cost on
this page, and it wants archiving after the first screen rather than after the
last.

The discipline that keeps it affordable is the one `AddExpenseIntent` already
found: don't rebuild the app inside a bubble. The compact presentation shows the
standing and one action, and anything more opens Dutch. A second front end is
also a second set of strings in both languages, for as long as the app exists.

*Cost: unmeasured, and the largest on this page — a second binary, plus a
`Localizable.xcstrings` that grows with every screen the extension draws. No
model change.*

---

## Localization

**Dutch speaks English and Polish.** One `Localizable.xcstrings` holds 252 keys,
an `InfoPlist.xcstrings` carries the camera prompt, there is no `.lproj` in the
source tree, and nothing is stale or untranslated. Polish shipped 2026-08-27,
partly through the repo's first outside contributions.

This section used to say the app was "not merely untranslated — unlocalizable as
written", and list the three things standing in front of a second language. All
three are done. What is kept here is what each one turned out to cost, because
none of them was the part that actually bit.

- **The strings became a catalog** — and nothing was extracted into it until
  `SWIFT_EMIT_LOC_STRINGS` was turned on. It was `NO` in all four build
  configurations, so only the hand-written symbolic keys existed and every
  `Text("Settings")` in the app stayed English whatever the phone was set to.
  Nothing warns about this; the catalog looks healthy the entire time, because
  the keys that *are* there are translated correctly.
- **Interpolated sentences became format strings**, and Polish justified the
  effort on the first line it touched: `"%@ pays %@ %@"` is translated
  `"%1$@ płaci %3$@ — odbiorca: %2$@"`. The amount moves ahead of the recipient
  and the recipient moves behind a dash. Without positional arguments that
  sentence cannot be written at all.
- **Plurals left Swift.** `GroupDetailView.count(_:_:_:)` is gone, replaced by
  catalog plural variations on the five counted strings. Polish needs four
  categories — `one`, `few`, `many`, `other` — where English needs two, so any
  `== 1 ? singular : plural` left in Swift is a bug for it. The trap on the way
  out is the opposite direction: moving a count into the catalog means adding
  the English `one`/`other` variations too, or English regresses to
  *"1 expenses"* while the translation is perfect.

### Two key conventions, in one catalog

Mistaking one for the other costs an afternoon, so: **78 of the keys are
symbolic** (`settleUp`, `addMembersFirst`, `about`), written by hand, marked
`extractionState: manual`, and used as `Text(.settleUp)` — Xcode generates those
static members from the catalog itself, which means grepping the source for
`"settleUp"` finds nothing and they read as dead entries. They are not. The
other **174 are English literals** extracted from `Text("…")` and
`String(localized:)`, where the key and the English text are the same string.

Both conventions are correct and they are not interchangeable. The literal one
is cheaper to write and reads better at the call site; the symbolic one is what
to reach for when the same English word needs two different translations. There
is a live example: `GroupSummaryStrings.localized` uses a symbolic key for
`fallbackTitle` rather than the literal `"Group"`, because that English word is
*also* an App Intents parameter label, and one shared key would force a single
Polish translation to serve both.

### The failure that hid the longest

**A `String`-typed helper returning an English literal is never localized**,
because `Text(someString)` resolves to the non-localizing initializer. No
warning, no stale key, nothing in the catalog to notice — the string simply
never had a key to begin with. These were all far from the screen and all
missed on the first pass: `Standing.caption`, `CloudSyncMonitor.describe`,
`PurchaseStore.message`, `JoinGroupView.message`, the App Intent answers and the
notification bodies. Every one is wrapped in `String(localized:)` now.

The rule that generalises: if a function returns `String` and that string
reaches a view, it needs the wrapper. A function returning `LocalizedStringKey`
or `LocalizedStringResource` cannot make this mistake, which is the better shape
where it fits.

### DutchKit still has no resource bundle

The shareable summary is the one place in the package that writes prose, and the
obvious fix — give DutchKit its own catalog — was declined on 2026-08-27.
`GroupSummary.text(locale:strings:)` takes a `GroupSummaryStrings` pack instead:
plain values, plus `@Sendable` closures for the lines that take arguments. The
app fills it from the single catalog it already ships, in
`Models/DTO/GroupSummaryStrings+Localized.swift`.

So a translator has one file to find rather than two, the package keeps no
resources and `swift test` still runs without a simulator, and
`GroupSummaryStrings.english` remains the default so the package's own tests
assert the text they always did. Measured at 2.5 KB, and no `.bundle` in the
app.

### Adding the next language

Close to what this section always promised — a translation pass and a column —
with three mechanical notes that are easy to lose:

- **`xcodebuild build` does not sync the catalog from source.** Only the Xcode
  IDE and `xcodebuild -exportLocalizations` do, so a literal added from the
  command line silently never becomes a key:

  ```
  xcodebuild -exportLocalizations -workspace Dutch.xcworkspace -scheme Dutch \
    -localizationPath <dir> -exportLanguage <code> CODE_SIGNING_ALLOWED=NO
  ```

  It rewrites `Localizable.xcstrings` in place. Afterwards, check for entries
  with no translation and for `extractionState: stale` — both are zero today.

- **A key written by hand has to match what the extractor emits, exactly.**
  Adding an entry to the catalog yourself is fine for a symbolic key and a trap
  for a literal one with more than one placeholder. The *key* is non-positional
  — `"%@ at %@"` — while the *translation* uses positional specifiers,
  `"%1$@ po kursie %2$@"`. Writing the key positionally instead produces an
  entry that looks perfect in the catalog, ships inside the built
  `pl.lproj/Localizable.strings`, and is never once looked up, because the
  runtime asks for a key that isn't there. The string stays English and nothing
  reports it. Caught on 2026-08-28 by running the export below and finding the
  invented key marked `extractionState: stale` beside the real one with no
  translation. **Export after hand-editing, then check for `stale`.**

- **Editing the catalog with a script needs Xcode's formatting**, which is
  `indent=2` with a space before the colon. A plain JSON dump reformats all
  three thousand lines and turns a two-key change into an unreviewable diff.

- **The app name is deliberately not translated.** `CFBundleDisplayName` and
  `CFBundleName` carry English only: *Dutch* is a brand and a pun on
  *going Dutch*, and neither survives translation.

*Cost: **92 KB measured**, archiving 2026-08-28 against the 1552 KB of
2026-08-20 — 1644 KB total, of which 1252 KB binary and an unchanged 212 KB
`Assets.car`. That splits into 64 KB of `.lproj` and 36 KB of binary for the
`String(localized:)` call sites and the generated symbolic members. The old
20–40 KB-per-language estimate on this line was right, at the top of its range:
**`pl.lproj` is 40 KB.***

*Worth knowing where the asymmetry comes from, because it decides what the third
language costs. `en.lproj/Localizable.strings` holds exactly 78 entries and
4.3 KB — only the symbolic keys, since the other 174 keys are already their own
English text. `pl.lproj` holds 247 entries and 21.2 KB, because every one of
them stores the full English key alongside the Polish. The English-literal-as-key
convention is free for English and paid for once per additional language.*

---

## Accessibility

The App Store listing carries accessibility labels, and a label is a claim. One
is left that Dutch cannot honestly make, audited 2026-07-29 against the 1.0
submission.

**Already true, and listed:** VoiceOver, Voice Control, Larger Text, Dark
Interface, and Differentiate Without Colour. The last one is designed in rather
than retrofitted — `Standing.caption` exists precisely so that owing and being
owed never rest on red versus green, and every amount on every screen is paired
with "you owe" or "you are owed". Larger Text holds because text uses semantic
styles throughout and nothing caps `dynamicTypeSize`; the three
`.font(.system(size:))` call sites are all `Image(systemName:)` glyphs, where a
fixed size is correct.

**Already true, and not yet listed:** Reduce Motion, since 2026-08-28 — see
**Reduce Motion** under Shipped. The code is done and the label is not, which is
the one direction of that mismatch nobody is harmed by.

### 14. Measure contrast, then claim it or fix it

**Measured 2026-09-04, and the guess above was wrong.** This entry used to read
"roughly 3.3:1 on white … so it probably passes". Red was close to that. Green
was nowhere near it:

| | on white | on grouped `F2F2F7` | AA-large, 3:1 |
|---|---|---|---|
| `.red` `FF3B30` | 3.55:1 | 3.18:1 | pass |
| `.green` `34C759` | **2.22:1** | **1.99:1** | **fail** |
| `.red` dark `FF453A` | 6.16:1 on black | 4.99:1 on `1C1C1E` | pass |
| `.green` dark `30D158` | 10.39:1 | 8.42:1 | pass |

The figures are bold and headline-sized, so 3:1 is the applicable bar rather
than 4.5:1 — and green missed it on both grounds. It is also the worse half to
lose: red says *you owe*, which the caption repeats anyway, while green is the
number people go looking for.

Light appearance now uses Apple's own Increase Contrast variants, `D70015` and
`248A3D` — 5.38:1 and 4.40:1 on white, 4.83:1 and 3.94:1 on grouped. Using
Apple's pair rather than an invented one means this is the palette the system
would already have swapped to for anyone with that setting on; it just stops
waiting to be asked.

Dark appearance was left on the semantic colours deliberately. It already passed
with room, and substituting a darker pair on a dark ground would have removed
contrast rather than added it.

Confined to `Standing.tint`, which is the amount text and nothing else —
`PaletteColor` still excludes red and green so a group's tint can't be mistaken
for a balance. `ErrorBanner`'s red is a glyph, not text, and clears the 3:1
non-text bar at 3.55:1. And colour was never the only carrier: `caption(isMe:)`
says the same thing in words, which makes this a WCAG 1.4.3 fix rather than a
1.4.1 one.

*Cost: zero bytes. The App Store listing still doesn't claim it — that is
metadata rather than a build, and is now a claim the app can actually support.*

---

## Not planned

These are the requests to expect, and the reasons they don't fit:

**Receipt photos.** Breaks all three constraints at once — CloudKit assets, sync
weight, storage, and an image pipeline in a codebase that currently rasterises
exactly one QR code.

**Live exchange rates.** Rates are frozen at entry deliberately (see
`DutchKit/Sources/DutchKit/ForeignAmount.swift`);
that decision is what stops a shared trip's balances from drifting and reopening
debts that were already settled. Fetching rates adds a network dependency, a
cache, and a failure mode in order to reintroduce the problem.

**A charts tab.** Swift Charts is system-provided so it's technically free, but
it's a screen nobody opens twice for a group with eleven expenses in it.

**An expense with no group.** Asked for as "let me split one dinner with one
person without making a group". The need is real; the shape isn't. Sharing runs
through the container's record zones, the free tier counts groups by which
persistent store they came from, and settlement is defined over a roster — a
group-less expense would need a second sharing mechanism and would sit outside
`GroupLimit` entirely.

What the request is actually describing is the ceremony of creating a group, not
the existence of one. The answer is a **"Split with…"** fast path that makes a
two-person group in a single step with a name already filled in. Zero model
change, and it fixes the friction rather than adding an entity that contradicts
the rest of the app.

**A backend, accounts, or login.** The absence of one is the design.

---

## Rules of thumb

- New logic goes in DutchKit if it can be tested without a simulator and without
  an iCloud account. Keep Core Data, SwiftUI and CloudKit types out of it.
- New model attributes are optional, arrive in a new model version, and mean
  **initializing and then promoting** the CloudKit schema before shipping — in
  that order. The container only creates fields in the Development schema as
  records carrying them actually sync, so an attribute nothing has populated
  never reaches the schema and the console reports "0 changes to deploy". Debug
  builds keep working against Development while TestFlight and the App Store
  fail against Production, which took out sharing entirely in 1.0. Run with
  `-initialize-cloudkit-schema` first, then deploy.
- Sync cannot be validated in a debug build. Development and Production are
  different schemas, and only a distributed build exercises the one users get —
  so a TestFlight sharing check belongs in every release.
- Prefer a system framework over a hand-rolled equivalent, and no framework over
  either.
