/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// A group's symbol on its colour, as a rounded tile.
///
/// Solid rather than a tinted wash behind a coloured glyph. The whole point is
/// to be recognisable from across the row before anything is read, and a 15%
/// fill reads as texture at a glance — the tile has to carry the colour.
struct GroupIcon: View {
    private let appearance: GroupAppearance
    private let base: CGFloat

    /// Scales with the user's type size, so the tile doesn't shrink into a dot
    /// next to a headline set at an accessibility size.
    @ScaledMetric private var scaled: CGFloat

    init(_ appearance: GroupAppearance, size: CGFloat = 38) {
        self.appearance = appearance
        self.base = size
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: .headline)
    }

    /// Capped, because the accessibility sizes scale by more than three times
    /// and an unbounded tile would push the name and the balance off the row
    /// entirely — the decoration would have eaten the content.
    private var side: CGFloat { min(scaled, base * 1.4) }

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
            .fill(appearance.color.tint.gradient)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: appearance.symbol.systemName)
                    .font(.system(size: side * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            // Decorative. The row it sits in reads as one sentence to VoiceOver,
            // and "airplane" spliced into the middle of it says nothing the name
            // hasn't already said.
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 12) {
            ForEach(PaletteColor.allCases) { color in
                GroupIcon(GroupAppearance(symbol: .airplane, color: color), size: 30)
            }
        }

        LazyVGrid(columns: Array(repeating: GridItem(), count: 6), spacing: 12) {
            ForEach(Emblem.allCases) { symbol in
                GroupIcon(GroupAppearance(symbol: symbol, color: .indigo))
            }
        }
    }
    .padding()
}
