/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

/// Where somebody stands in a group: owing, owed, or even.
///
/// Three cases rather than a signed `Money` carried around with a sign test at
/// each call site, so that "even" is a state of its own. An earlier version
/// tinted by sign alone and rendered a zero balance green, which reads as being
/// owed money.
///
/// Shared between the group list and the detail screen because both answer the
/// same question — the list for the person holding the phone, the detail screen
/// for every member — and phrasing or colouring them differently would make the
/// same balance look like two different facts.
enum Standing: Equatable {
    case owes(Money)
    case isOwed(Money)
    case settled

    /// A net position as a standing. `nil` — a member the settlement has no
    /// balance for — is even, which is what a member with no expenses is.
    init(balance: Money?) {
        guard let balance, !balance.isZero else {
            self = .settled
            return
        }
        self = balance < .zero ? .owes(balance.magnitude) : .isOwed(balance)
    }

    /// The colour the amount is drawn in.
    ///
    /// **Not** the semantic `.red` and `.green` in light appearance, and that is
    /// a contrast fix rather than a taste one. Measured 2026-09-04 against WCAG
    /// 2.1, on both grounds the amount actually appears over — plain white and
    /// the grouped-list `F2F2F7`:
    ///
    /// | | on white | on grouped |
    /// |---|---|---|
    /// | `.red` `FF3B30` | 3.55:1 | 3.18:1 |
    /// | `.green` `34C759` | 2.22:1 | 1.99:1 |
    ///
    /// These figures are bold and headline-sized, so the bar is AA's 3:1 for
    /// large text and not 4.5:1 — and green misses it on both grounds, badly.
    /// It is also the worse one to lose: red says you owe, which the caption
    /// repeats, while green is the figure people go looking for.
    ///
    /// The replacements are Apple's own Increase Contrast variants rather than
    /// invented ones, so this is the palette the system would already swap to
    /// for anyone with that setting turned on — it just stops waiting to be
    /// asked. They measure 5.38:1 and 4.40:1 on white, 4.83:1 and 3.94:1 on
    /// grouped: clear of 3:1 everywhere, and red clears 4.5:1 outright.
    ///
    /// Dark appearance deliberately keeps the semantic colours. They already
    /// measure 4.99:1 and 8.42:1 against `1C1C1E`, and substituting a *darker*
    /// pair on a dark ground would take contrast away rather than add it.
    ///
    /// Narrow on purpose: the amount text only, never the palette. `PaletteColor`
    /// excludes red and green precisely so a group's tint can't be mistaken for
    /// a balance, and widening this would spend that distinction. Colour is not
    /// the sole carrier either way — `caption(isMe:)` says the same thing in
    /// words — which is what keeps this a WCAG 1.4.3 question rather than a
    /// 1.4.1 one.
    var tint: Color {
        switch self {
        case .owes: Self.owing
        case .isOwed: Self.owed
        case .settled: .secondary
        }
    }

    /// Resolved once and cached; the closure re-runs on every trait change, so
    /// this still follows the user into and out of dark mode.
    private static let owing = adaptive(light: UIColor(red: 215 / 255, green: 0, blue: 21 / 255, alpha: 1), dark: .systemRed)
    private static let owed = adaptive(light: UIColor(red: 36 / 255, green: 138 / 255, blue: 61 / 255, alpha: 1), dark: .systemGreen)

    /// Hardcoded components, against the rule everywhere else in this app, and
    /// the exception is the point: a semantic colour is the thing that failed
    /// here. The values are transcribed from Apple's high-contrast palette and
    /// carry their measured ratios above, so what ships is what was measured —
    /// resolving them out of `UITraitCollection` at runtime would be prettier
    /// and would silently re-open the question every time Apple retunes.
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    /// Redundant to the colour on purpose. Colour alone can't carry the
    /// difference between owing and being owed: it fails for anyone with a
    /// red/green deficiency, and VoiceOver never sees it at all.
    func caption(isMe: Bool) -> String {
        switch self {
        case .owes: isMe ? String(localized: "you owe") : String(localized: "owes")
        case .isOwed: isMe ? String(localized: "you are owed") : String(localized: "is owed")
        case .settled: String(localized: "settled up")
        }
    }

    /// The whole standing as a sentence, for VoiceOver.
    func accessibleValue(isMe: Bool, currencyCode: String) -> String {
        switch self {
        case .owes(let amount):
            let money = amount.formatted(currencyCode: currencyCode)
            return isMe ? String(localized: "You owe \(money)") : String(localized: "Owes \(money)")
        case .isOwed(let amount):
            let money = amount.formatted(currencyCode: currencyCode)
            return isMe
                ? String(localized: "You are owed \(money)")
                : String(localized: "Is owed \(money)")
        case .settled:
            return String(localized: "Settled up")
        }
    }
}
