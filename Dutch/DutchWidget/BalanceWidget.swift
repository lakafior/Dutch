/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI
import UIKit
import WidgetKit

/// "You owe €42 · Lisbon 2026" on the Home Screen and the Lock Screen.
///
/// Leads with the group last opened in the app — the trip somebody is on, and
/// the same answer the quick action and Siri use. Not configurable yet: a picker
/// would need a group query running in this process, and the snapshot holds
/// everything needed to add one later.
struct BalanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "net.smigi.Dutch.Balance", provider: SnapshotProvider()) { entry in
            BalanceWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Balance")
        .description("What you owe or are owed in the group you opened last.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// One entry, never refreshed on a schedule. The figures only change when the
/// app saves or syncs, and the app reloads this widget itself when they do —
/// polling would spend WidgetKit's refresh budget to redraw the same numbers.
struct SnapshotProvider: TimelineProvider {
    private static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.net.smigi.Dutch")?
            .appendingPathComponent(WidgetSnapshot.fileName)
    }

    private static func read() -> WidgetSnapshot {
        url.map(WidgetSnapshot.read) ?? .empty
    }

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    /// The gallery shows the real groups when there are any, and the sample
    /// otherwise — an empty widget in the gallery advertises nothing.
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let real = Self.read()
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview && real.groups.isEmpty ? .sample : real))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: .now, snapshot: Self.read())], policy: .never))
    }
}

// MARK: - Views

struct BalanceWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color(uiColor: .systemBackground) }
    }

    @ViewBuilder
    private var content: some View {
        let groups = snapshot.ordered(limit: family == .systemMedium ? 2 : 1)
        if let first = groups.first {
            switch family {
            case .systemMedium:
                MediumView(groups: groups)
            case .accessoryRectangular:
                RectangularView(group: first)
                    .widgetURL(DutchLink.group(first.id).url)
            case .accessoryInline:
                InlineView(group: first)
                    .widgetURL(DutchLink.group(first.id).url)
            default:
                SmallView(group: first)
                    .widgetURL(DutchLink.group(first.id).url)
            }
        } else {
            NoGroupsView(family: family)
        }
    }
}

/// The trip you're on: its tile and name, then the one number.
private struct SmallView: View {
    let group: WidgetSnapshot.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                GroupTile(group: group, side: 30)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            Text(group.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Figure(group: group, amountFont: .title2.weight(.bold))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Two groups, the trip you're on first, and a button for a new expense in it.
/// Each row opens its own group.
///
/// Two rather than three: a third row leaves no room for the button, and the
/// button is the one thing here that saves more than a glance.
private struct MediumView: View {
    let groups: [WidgetSnapshot.Group]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                Link(destination: DutchLink.group(group.id).url) {
                    HStack(spacing: 10) {
                        GroupTile(group: group, side: 26)
                        Text(group.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Figure(group: group, amountFont: .subheadline.weight(.bold), alignment: .trailing)
                    }
                }
                Divider()
            }
            Spacer(minLength: 0)
            if let first = groups.first {
                NewExpenseLink(groupID: first.id)
            }
        }
    }
}

private struct NewExpenseLink: View {
    let groupID: UUID

    var body: some View {
        Link(destination: DutchLink.newExpense(groupID).url) {
            Label("New Expense", systemImage: "plus.circle.fill")
                .font(.footnote.weight(.semibold))
        }
    }
}

/// Lock Screen: three lines, monochrome — the system tints accessory widgets
/// itself, so colour would only be thrown away.
private struct RectangularView: View {
    let group: WidgetSnapshot.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(group.name, systemImage: group.symbolName)
                .font(.headline)
                .lineLimit(1)
            Figure(group: group, amountFont: .title3.weight(.bold), tinted: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line above the clock. One sentence; the system truncates anything longer.
private struct InlineView: View {
    let group: WidgetSnapshot.Group

    var body: some View {
        switch Standing(group) {
        case .owes(let amount):
            Text("\(group.name): you owe \(amount.formatted(currencyCode: group.currencyCode))")
        case .isOwed(let amount):
            Text("\(group.name): you are owed \(amount.formatted(currencyCode: group.currencyCode))")
        case .settled:
            Text("\(group.name): settled up")
        case .unknown:
            Text("\(group.name): \(group.totalSpent.formatted(currencyCode: group.currencyCode))")
        }
    }
}

/// The amount and the words for it. The words are not decoration: the colour
/// alone must never be what says which way the money goes.
private struct Figure: View {
    let group: WidgetSnapshot.Group
    let amountFont: Font
    var alignment: HorizontalAlignment = .leading
    var tinted = true

    var body: some View {
        let standing = Standing(group)
        VStack(alignment: alignment, spacing: 0) {
            switch standing {
            case .owes(let amount), .isOwed(let amount):
                Text(amount.formatted(currencyCode: group.currencyCode))
                    .font(amountFont)
                    .foregroundStyle(tinted ? standing.tint : .primary)
                    .privacySensitive()
            case .settled:
                Text("Settled up")
                    .font(amountFont)
                    .foregroundStyle(.secondary)
            case .unknown:
                Text(group.totalSpent.formatted(currencyCode: group.currencyCode))
                    .font(amountFont)
                    .privacySensitive()
            }
            Text(standing.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .minimumScaleFactor(0.6)
        .lineLimit(1)
    }
}

private struct NoGroupsView: View {
    let family: WidgetFamily

    var body: some View {
        if family == .accessoryInline {
            Text("No Groups")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("No Groups")
                    .font(.headline)
                Text("Create a group in Dutch to see your balance here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(DutchLink.newExpense(nil).url)
        }
    }
}

/// The group's symbol on its colour, as in the app's list.
private struct GroupTile: View {
    let group: WidgetSnapshot.Group
    let side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(Palette.color(named: group.colorName).gradient)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: group.symbolName)
                    .font(.system(size: side * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

// MARK: - Standing, as the widget reads it

/// The app's `Standing`, plus the case the app's list handles by showing the
/// total instead: no identity, so no "you".
private enum Standing {
    case owes(Money), isOwed(Money), settled, unknown

    init(_ group: WidgetSnapshot.Group) {
        guard let balance = group.myBalance else { self = .unknown; return }
        if balance.isZero { self = .settled }
        else { self = balance < .zero ? .owes(balance.magnitude) : .isOwed(balance) }
    }

    var caption: LocalizedStringKey {
        switch self {
        case .owes: "you owe"
        case .isOwed: "you are owed"
        case .settled: "everyone's even"
        case .unknown: "total spent"
        }
    }

    /// The same high-contrast pair as the app's `Standing.tint` — see the
    /// measurements there. Dark appearance keeps the system colours.
    var tint: Color {
        switch self {
        case .owes: Self.adaptive(light: UIColor(red: 215 / 255, green: 0, blue: 21 / 255, alpha: 1), dark: .systemRed)
        case .isOwed: Self.adaptive(light: UIColor(red: 36 / 255, green: 138 / 255, blue: 61 / 255, alpha: 1), dark: .systemGreen)
        case .settled, .unknown: .secondary
        }
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The app's `PaletteColor`, by name. A name the widget doesn't know — written
/// by a newer app — falls back to blue rather than failing.
private enum Palette {
    static func color(named name: String) -> Color {
        switch name {
        case "teal": .teal
        case "indigo": .indigo
        case "purple": .purple
        case "pink": .pink
        case "orange": .orange
        case "brown": .brown
        case "gray": .gray
        default: .blue
        }
    }
}

// MARK: - Sample

extension WidgetSnapshot {
    /// The widget gallery's example, in the same Lisbon trip the App Store
    /// screenshots use.
    static let sample = WidgetSnapshot(groups: [
        .init(id: UUID(), name: "Lisbon 2026", currencyCode: "EUR", symbolName: "airplane", colorName: "teal",
              totalSpentCents: 113_350, myBalanceCents: -20_014, pendingTransfers: 5),
        .init(id: UUID(), name: "Tokyo", currencyCode: "EUR", symbolName: "map.fill", colorName: "pink",
              totalSpentCents: 118_289, myBalanceCents: 12_925, pendingTransfers: 2),
        .init(id: UUID(), name: "Book Club", currencyCode: "EUR", symbolName: "book.fill", colorName: "gray",
              totalSpentCents: 21_000, myBalanceCents: 0, pendingTransfers: 0),
    ], lastOpenedGroupID: nil)
}

#Preview(as: .systemSmall) {
    BalanceWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}

#Preview(as: .systemMedium) {
    BalanceWidget()
} timeline: {
    SnapshotEntry(date: .now, snapshot: .sample)
}
