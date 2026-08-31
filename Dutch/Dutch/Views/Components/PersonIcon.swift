/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// A person's initials on their colour, as a circle.
///
/// A circle where `GroupIcon` is a rounded square, following the convention
/// every Apple app uses — Contacts, Messages, Mail. It is the difference that
/// makes a member row and a group row tell themselves apart at a glance, which
/// matters here because the two appear one screen apart and carry the same
/// palette.
struct PersonIcon: View {
    private let avatar: PersonAvatar
    private let base: CGFloat

    /// Scales with the user's type size, so the circle doesn't shrink into a
    /// dot next to a name set at an accessibility size.
    @ScaledMetric private var scaled: CGFloat

    init(_ avatar: PersonAvatar, size: CGFloat = 30) {
        self.avatar = avatar
        self.base = size
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    /// Capped for the same reason as `GroupIcon`: the accessibility sizes scale
    /// by more than three times, and an unbounded circle would push the name and
    /// the balance off the row entirely.
    private var side: CGFloat { min(scaled, base * 1.4) }

    var body: some View {
        Circle()
            .fill(avatar.color.tint.gradient)
            .frame(width: side, height: side)
            .overlay {
                if let symbol = avatar.symbol {
                    // Ahead of the initials, not beside them: a circle 30pt
                    // across fits one thing, and a member who picked a glyph
                    // picked it *instead of* the letters.
                    Image(systemName: symbol.systemName)
                        .font(.system(size: side * 0.44))
                        .foregroundStyle(.white)
                } else if let initials = avatar.initials {
                    Text(initials)
                        .font(.system(size: side * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                        // Two wide characters — "WM", or one CJK glyph pair —
                        // overflow a circle sized for "AK". Shrinking beats
                        // clipping a letter in half.
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: side * 0.44))
                        .foregroundStyle(.white)
                }
            }
            // Decorative. The row it sits in reads as one sentence to VoiceOver,
            // and "AK" spliced into the middle of it says nothing the name
            // hasn't already said.
            .accessibilityHidden(true)
    }
}

#Preview {
    // Real names through the real parser rather than initials typed out by
    // hand, so the preview shows what the app will — two initials, one, a
    // non-Latin script, a particle surname, and the no-name fallback. `zip`
    // truncates, so growing the palette can't index past the end.
    let names: [String?] = [
        "Anna Kowalska", "Bruno", "山田太郎", "Ada van der Berg",
        nil, "Émile Zola", "Wei Wu", "🎉",
    ]

    List {
        ForEach(Array(zip(names, PaletteColor.allCases)), id: \.1) { name, color in
            HStack(spacing: 12) {
                PersonIcon(PersonAvatar(initials: PersonAvatar.initials(from: name), color: color))
                Text(name ?? "No name")
            }
        }
    }
}
