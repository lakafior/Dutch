/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import SwiftUI

struct MemberBalanceRow: View {
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
        case (true, true): String(localized: "\(name), you, linked to iCloud")
        case (true, false): String(localized: "\(name), you")
        case (false, true): String(localized: "\(name), joined on iCloud")
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

                // `.caption`, not `.caption2`. This line is what carries the
                // difference between owing and being owed for anyone the
                // colour doesn't reach — see the note on `Standing.tint`,
                // which leans on exactly this redundancy to stay a WCAG 1.4.3
                // question rather than a 1.4.1 one. Setting it in the smallest
                // type the system offers spent most of what that buys.
                Text(standing.caption(isMe: isMe))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: balance)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleName)
        .accessibilityValue(standing.accessibleValue(isMe: isMe, currencyCode: currencyCode))
    }
}
