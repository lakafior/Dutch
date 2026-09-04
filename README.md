<div align="center">

<img src="website/assets/icon.png" width="112" height="112" alt="">

# Dutch

**Split a dinner, a trip or a flat — and always know who owes what.**

No accounts. No servers. No trackers. Smaller than a photo.

[![Download on the App Store](https://img.shields.io/badge/App_Store-Download-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/app/id6795190862)
[![Website](https://img.shields.io/badge/dutch.smigi.net-Website-1f2937?style=for-the-badge)](https://dutch.smigi.net)
[![Po polsku](https://img.shields.io/badge/dutch.smigi.net%2Fpl-Po_polsku-1f2937?style=for-the-badge)](https://dutch.smigi.net/pl/)

[![License: MPL 2.0](https://img.shields.io/badge/license-MPL--2.0-brightgreen.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-lightgrey.svg)](#-building--testing)
[![Languages](https://img.shields.io/badge/languages-English%20%C2%B7%20Polski-629dff.svg)](#what-it-does)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-success.svg)](#-technology-stack-pure-apple)
[![DutchKit tests](https://github.com/lakafior/Dutch/actions/workflows/ci.yml/badge.svg)](https://github.com/lakafior/Dutch/actions/workflows/ci.yml)

<img src="website/assets/shot-list.jpg" width="30%" alt="The Dutch group list, showing eight groups with the balance owed or owed to you in each.">
<img src="website/assets/shot-detail.jpg" width="30%" alt="A group's detail screen: total spent, each member's balance, and the two payments that settle the group.">
<img src="website/assets/shot-share.jpg" width="30%" alt="The share screen, showing a QR code and the group's word sequence.">

</div>

---

## Everyone's in, in about a minute

You're at the table, the bill has arrived, and nobody wants to install an app and
make an account before the coffee gets cold.

So Dutch doesn't have accounts. Show your group's QR code, everyone scans it, and
they're in. Every group also gets a short word sequence like **green-moon-tea**,
so two people can check they've landed in the same place.

From there the app keeps a running answer to one question: **who owes whom, and
how few payments would clear it.**

## What it does

| | |
| :--- | :--- |
| **Who owes whom** | Not just a running total — the shortest list of payments that squares everybody up. Mark one paid and the balances clear. |
| **Any currency** | Paid in yen on a trip priced in euros? Enter the rate you actually got. It converts once, so the balance never drifts afterwards. |
| **Uneven splits** | Split evenly, leave someone out, or give one person a double share, as a percentage of a full share. Every remaining cent is distributed, never dropped. |
| **Exact to the cent** | Money is held as integer cents, so a three-way split never loses a penny to floating point. |
| **Live for everyone** | Add an expense and it appears on everybody's phone, through CloudKit — no server in the middle to trust or pay for. |
| **Editable and duplicable** | Correct an expense in place rather than deleting it, or touch and hold a round at the bar to enter the next one. |
| **"You owe", not your name** | Tell the app which member you are and it speaks in the second person. Kept on the device, never synced. |
| **Siri and Shortcuts** | "Add an expense to Berlin Trip." Ask Siri what you owe, or build the app into a Shortcut of your own. |
| **Spotlight and quick actions** | Search your groups from the Home Screen, or long-press the icon to add an expense to the one you were last in. |
| **Told when it changes** | Optional notifications when somebody else adds an expense, so checking the balance isn't something you have to remember to do. Off until you turn them on. |
| **Fully offline** | Everything is written to Core Data locally and syncs when the device reconnects. |
| **English and Polish** | The whole app, including the summary you share with the group. Adding a language is a column in one string catalogue rather than a rewrite, so if you want yours, [say so](https://github.com/lakafior/Dutch/issues). |

Where the app is going next, and what it deliberately won't do, is in
[ROADMAP.md](ROADMAP.md).

## Free, and paid

Every feature works on the free tier — no ads, no trial, no nagging. The one
limit is that you can **create** one group at a time. Groups you *join* never
count, so scanning a friend's code is always free however many times you do it.

Lifting the limit is a single purchase (not a subscription, and Family
Shareable). The price is never written in this source — it comes from StoreKit
so it is already localized for the reader's storefront.

And because the source is open: **build it yourself and the limit isn't there at
all.** What the App Store version buys you is not having to.

## Privacy

Dutch has no backend. There is no server that holds your expenses, no account to
create, and no analytics of any kind. Your groups live in *your* iCloud, and
sharing a group is Apple's own CloudKit sharing — the same mechanism as a shared
photo album.

That isn't a policy that could change next quarter. There is nowhere for the data
to go, because the infrastructure to collect it was never built.
[Full privacy policy →](https://dutch.smigi.net/privacy/)

---

## 🧠 How the sync works

Unlike a standard client–server app, **there is no single source of truth** owned
by us.

1. **Private storage** — every user has their own private CloudKit database.
2. **Shared zones** — when user **A** creates a group, the app creates a dedicated custom zone in their private database for it.
3. **Invitations** — **A** taps "Share Group", which presents `UICloudSharingController` and sends an iCloud invitation (iMessage, Mail, or a link). The same URL is also rendered as a QR code.
4. **Joining** — once **B** accepts, CloudKit grants them read/write access to that zone and their device downloads the group's data.
5. **Continuous sync** — from then on, every change by **A** or **B** is uploaded and pushed to the other participants via silent push notifications.
6. **Conflict handling** — concurrent offline edits are resolved per-property, favouring the incoming change (`NSMergeByPropertyObjectTrumpMergePolicy`).

**In short:** the source of truth is distributed across the users' own iCloud
spaces, mediated by CloudKit — serverless by design.

### Why notifications are *local*

Having no server has one honest cost, and this is it. A normal app's push
notification is composed and sent by its backend; Dutch has no backend to send
one. So a notification here is **composed by your own phone**, about data it has
already downloaded:

CloudKit wakes the app with a silent push → `NSPersistentCloudKitContainer`
imports → Core Data's persistent history says *what* arrived → the app posts a
local notification for the expenses somebody else added.

The banner arrives without you opening the app, which is the point. But it is
best-effort by construction, and the app says so rather than pretending
otherwise: iOS decides when to deliver a silent push, delays them in Low Power
Mode, and **delivers none at all to an app you have force-quit**. Turning off
Background App Refresh for Dutch stops them too. Opening the app always shows
the truth.

Expenses you entered yourself are filtered out — including the ones that arrive
from your own second device — so the only thing that interrupts you is somebody
else spending money.

### Why there are two persistent stores

`PersistenceController` loads **two** stores against the same model, and both are
required:

- the **private** store mirrors to the user's own CloudKit database and holds groups they created;
- the **shared** store receives groups other people have shared *with* them.

With only the private store, accepting an invitation appears to succeed but the
group never appears — Core Data has nowhere to put it.

> **Note on word sequences:** they are *labels, not credentials*. Access to a
> group is granted solely by the CloudKit share the QR code carries. A matching
> word sequence is never treated as proof of membership.

---

## 🛠 Technology stack (pure Apple)

This project has **zero external dependencies** — no CocoaPods, no Carthage, and
no remote Swift packages. Everything is built on official Apple frameworks.

| Framework / Tool | Purpose |
| :--- | :--- |
| **SwiftUI** | The entire user interface. |
| **UIKit** | Bridged in only where SwiftUI has no equivalent (share sheet, camera). |
| **Core Data** | Local on-device persistence. |
| **CloudKit** | Remote storage and sync infrastructure. |
| `NSPersistentCloudKitContainer` | The bridge that mirrors Core Data into CloudKit. |
| `UICloudSharingController` | System UI for sharing a group with other iCloud users. |
| **StoreKit 2** | The one in-app purchase. |
| **App Intents** | Siri, Shortcuts and the Home Screen quick action. |
| **Core Spotlight** | Making groups searchable from the Home Screen. |
| **UserNotifications** | Local notifications about expenses that arrived from other people. |
| `NSPersistentHistoryTransaction` | Working out *what* a CloudKit import brought down, while the app is in the background. |
| `CoreImage` | Generating QR codes from share URLs. |
| `AVFoundation` | Scanning QR codes with the device camera. |
| **Swift Testing** | Unit tests (`@Test` / `@Suite`); UI tests use XCTest. |

There is one Swift package in the repo — **DutchKit** — but it is *local*, living
inside this repository rather than being fetched from anywhere.

## 🧩 Two modules

The code is split in two, along a single line: **does it need Apple's frameworks
to work?**

### `DutchKit` — the rules of the money

A local Swift package with no UI, no persistence, and no CloudKit. Just
Foundation, in Swift 6 language mode.

| File | Responsibility |
| :--- | :--- |
| `Money.swift` | A monetary amount as whole cents (`Int`), with even and weighted splits that always reconcile back to the total. |
| `SettlementCalculator.swift` | Balances per person, how one expense divides between its sharers, and the transfers that settle a group in at most *n − 1* payments. |
| `ForeignAmount.swift` | An amount as it was paid abroad, plus the rate it was captured at — converted once, never re-read. |
| `GroupSummary.swift` | Rendering a group as shareable plain text. |
| `WordGenerator.swift` | Human-readable sequences such as `coral-lotus-pearl`. |

Because it touches nothing platform-specific, its tests run from the command line
in milliseconds — no simulator, no iCloud account. That is also why the package
declares a macOS platform it never actually ships to.

### `Dutch` — everything that touches Apple

The app target: SwiftUI views, the Core Data stack, CloudKit sharing, the QR
scanner, StoreKit, App Intents.

The two meet in exactly one file, `Models/DTO/SettlementBridge.swift`, which maps
Core Data objects (`ExpenseGroup`, `Person`, `Expense`) onto DutchKit's value
types (`Participant`, `ExpenseEntry`) and calls the calculator. Keeping the
conversion in one place means the settlement maths never learns that Core Data
exists.

---

## 📁 Project structure

```plaintext
Dutch/                              # repository root
├── website/                        # the marketing site (static HTML, no build step)
│   └── pl/                         # …and its Polish translation, cross-linked with hreflang
└── Dutch/                          # ← open Dutch.xcworkspace from here
    ├── Dutch.xcworkspace           # the workspace (app + package)
    ├── Dutch.xcodeproj
    ├── Dutch.storekit              # simulator-only StoreKit configuration
    ├── Design/                     # icon source + the renderer that emits the PNGs
    ├── Dutch/                      # app target
    │   ├── App/
    │   │   ├── DutchApp.swift             # @main, plus the scene delegate that accepts shares
    │   │   └── AppRouter.swift            # app-level navigation state (intents, share acceptance)
    │   ├── Models/
    │   │   ├── CoreData/
    │   │   │   ├── PersistenceController.swift  # private + shared CloudKit stores
    │   │   │   └── Dutch.xcdatamodeld           # ExpenseGroup, Person, Expense (v6)
    │   │   └── DTO/
    │   │       └── SettlementBridge.swift       # Core Data ↔ DutchKit
    │   ├── Views/
    │   │   ├── Main/                      # ContentView, GroupListView, GroupDetailView
    │   │   ├── Expenses/                  # ExpenseFormView (adds and edits)
    │   │   ├── Sharing/                   # ShareGroupView, JoinGroupView,
    │   │   │                              # QRScannerView, CloudSharingSheet
    │   │   ├── Purchase/                  # PaywallView
    │   │   ├── Settings/                  # SettingsView (notifications + about)
    │   │   └── Components/                # GroupIcon, Standing, SyncStatusIndicator, …
    │   ├── Services/
    │   │   ├── CloudSharingService.swift  # creating and accepting CKShares
    │   │   ├── CloudSyncMonitor.swift     # surfacing mirroring failures to the UI
    │   │   ├── GroupStore.swift           # all write operations
    │   │   ├── GroupLimit.swift           # the free tier's one-created-group rule
    │   │   ├── PurchaseStore.swift        # StoreKit 2 entitlement
    │   │   ├── ExpenseDefaults.swift      # per-group state local to this device
    │   │   ├── CloudIdentity.swift        # which iCloud account this device is
    │   │   ├── ExpenseNotifier.swift      # local notifications for imported expenses
    │   │   ├── SpotlightIndexer.swift
    │   │   └── QRCodeGenerator.swift
    │   └── Intents/                       # App Intents, self-contained on purpose
    ├── DutchKit/                   # local Swift package (pure logic)
    │   ├── Sources/DutchKit/
    │   └── Tests/DutchKitTests/
    ├── DutchTests/                 # Core Data + bridge tests (Swift Testing)
    └── DutchUITests/               # end-to-end flows (XCTest)
```

There are deliberately **no view models**. Reads go through `@FetchRequest` so
that changes synced down from CloudKit reach the UI on their own; writes are
funnelled through `GroupStore`.

---

## 🚀 Building & testing

Requires **Xcode 26 or newer**; the app targets **iOS 17+**. All commands run
from the inner `Dutch/` directory.

Build the app:

```bash
xcodebuild -workspace Dutch.xcworkspace -scheme Dutch -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

Run the pure logic tests — fast, and no simulator needed:

```bash
swift test --package-path DutchKit
```

Run the full suite, including Core Data and UI tests:

```bash
xcodebuild -workspace Dutch.xcworkspace -scheme Dutch -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

To run on a device you will need to set your own **Development Team** in the
target's Signing & Capabilities tab, and — because the app uses CloudKit and push
— your own iCloud container and app group identifier in `Dutch.entitlements`.

Sync itself cannot be tested in the simulator alone: it needs two devices signed
in to **different** iCloud accounts, and a paid developer account for the
CloudKit container and push entitlements. The tests run against an in-memory
store with mirroring switched off, so they exercise the data model and the
settlement maths rather than CloudKit.

> **Publishing a fork?** Change the display name, bundle identifier, app group,
> iCloud container and app icon first — the Dutch name and icon aren't covered by
> the code licence. See [TRADEMARK.md](TRADEMARK.md).

---

## 🤝 Contributing

Bug reports, ideas and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md). Before opening a feature request, it is worth
reading the **Not planned** section of [ROADMAP.md](ROADMAP.md), which explains
what the app deliberately leaves out and why.

## 📄 License

Dutch is free software under the **Mozilla Public License 2.0**. See
[LICENSE](LICENSE).

You are free to use, modify and distribute it, including commercially.
Modifications to existing MPL-licensed files must be released under the same
licence; you may combine this code with proprietary code in separate files as
part of a larger work.

The **name "Dutch" as this app's name, and the app icon**, are not part of that
grant — MPL-2.0 §2.3 grants no trademark or logo rights. Fork freely and ship
what you build, but ship it under your own name and your own icon. See
[TRADEMARK.md](TRADEMARK.md) for the details, and email `dutch@smigi.net` if you
want to use the brand for something.
