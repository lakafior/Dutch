/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// The palette as a grid of swatches. Renders as a row, so it goes inside a
/// `Section` in whatever `Form` is presenting it.
///
/// Shared by everything that lets somebody pick a colour — a group's, in
/// `AppearancePicker`, and a member's, in `EditMemberSheet`. One grid rather
/// than two, so the two cannot drift into different swatch sizes, different tap
/// targets or different selection marks while claiming to offer the same eight
/// colours.
struct PaletteColorGrid: View {
    @Binding var selection: PaletteColor

    /// A tap target of 44 with a smaller swatch inside it, rather than a 28pt
    /// button that happens to be easy to miss.
    private let target: CGFloat = 44

    var body: some View {
        // Wrapping rather than a horizontal scroll: eight swatches fit across
        // every phone at ordinary type sizes, and a row that scrolls hides
        // choices behind a gesture nobody knows is there.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: target), spacing: 4)], spacing: 4) {
            ForEach(PaletteColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(color.tint.gradient)
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay {
                            Circle()
                                .strokeBorder(color.tint, lineWidth: 2)
                                .opacity(selection == color ? 1 : 0)
                        }
                        .frame(width: target, height: target)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.label)
                .accessibilityAddTraits(selection == color ? [.isSelected] : [])
            }
        }
        .animation(.snappy, value: selection)
        // On the grid rather than on whatever is presenting it, so a colour
        // picked anywhere feels the same. `AppearancePicker` triggers on the
        // symbol alone for that reason — leaving it on the whole appearance
        // would fire twice for one tap on a swatch.
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colour")
    }
}

/// Picks a group's symbol and colour. Renders as rows, so it goes inside a
/// `Section` in whatever `Form` is presenting it.
///
/// There is no separate preview tile: the grid shows every symbol in the colour
/// currently chosen, so picking a colour re-tints the thing being chosen and the
/// selection *is* the preview. A swatch plus a grid plus a large sample of the
/// two combined is three ways of saying the same thing in one sheet.
struct AppearancePicker: View {
    @Binding var appearance: GroupAppearance

    /// A tap target of 44 with a smaller mark inside it, rather than a 30pt
    /// button that happens to be easy to miss.
    private let target: CGFloat = 44

    var body: some View {
        Group {
            PaletteColorGrid(selection: $appearance.color)
            symbols
        }
    }

    // MARK: - Symbols

    /// A group always has a symbol, so the grid it gets offers no way back to
    /// "none" — where a member's does, initials being the thing a member falls
    /// back to. The binding bridges the two: clearing is unreachable from this
    /// grid, and a `nil` that arrived some other way leaves the symbol alone.
    private var symbols: some View {
        EmblemGrid(
            selection: Binding(
                get: { appearance.symbol },
                set: { appearance.symbol = $0 ?? appearance.symbol }
            ),
            tint: appearance.color,
            includesNone: false
        )
    }
}

/// The curated symbols as a grid of marks, tinted with whatever colour the
/// thing being styled is currently wearing. Renders as a row, so it goes inside
/// a `Section` in whatever `Form` is presenting it.
///
/// Shared by groups and members for the reason `PaletteColorGrid` is shared:
/// one grid cannot drift into two swatch sizes, two tap targets or two
/// selection marks while claiming to offer the same two dozen symbols.
struct EmblemGrid: View {
    @Binding var selection: Emblem?
    var tint: PaletteColor
    /// Whether the grid offers a way back to no symbol at all. A group always
    /// has one; a member without one is drawn as initials, which is the default
    /// and has to stay reachable.
    var includesNone = true

    /// A tap target of 44 with a smaller mark inside it, rather than a 30pt
    /// button that happens to be easy to miss.
    private let target: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: target), spacing: 4)], spacing: 4) {
            if includesNone {
                // First, and drawn as a person rather than as a slash or an
                // empty circle: this is not "clear the field", it is the other
                // way a member can look, and `PersonIcon` draws exactly this
                // glyph for somebody whose name yields no initials.
                button(for: nil, systemName: "textformat.abc", label: .emblemInitials)
            }

            ForEach(Emblem.allCases) { symbol in
                button(for: symbol, systemName: symbol.systemName, label: symbol.label)
            }
        }
        .animation(.snappy, value: selection)
        .animation(.snappy, value: tint)
        .sensoryFeedback(.selection, trigger: selection)
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Symbol")
    }

    private func button(
        for symbol: Emblem?,
        systemName: String,
        label: LocalizedStringResource
    ) -> some View {
        Button {
            selection = symbol
        } label: {
            mark(systemName: systemName, isSelected: selection == symbol)
                .frame(width: target, height: target)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selection == symbol ? [.isSelected] : [])
    }

    private func mark(systemName: String, isSelected: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? Color.white : Color.secondary)
            .frame(width: 36, height: 36)
            // Two layers rather than one fill chosen by a ternary, so the
            // colour crossfades in on selection instead of the shape style
            // being swapped out from under the animation.
            .background {
                Circle().fill(.fill.quaternary)
            }
            .background {
                Circle()
                    .fill(tint.tint.gradient)
                    .opacity(isSelected ? 1 : 0)
            }
    }
}

#Preview {
    @Previewable @State var appearance = GroupAppearance(symbol: .airplane, color: .indigo)

    Form {
        Section("Appearance") {
            AppearancePicker(appearance: $appearance)
        }
    }
}
