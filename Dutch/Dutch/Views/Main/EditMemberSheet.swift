/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// Sheet for renaming one member and choosing how their circle looks.
///
/// Reached by touch-and-hold rather than by a control on the members list, for
/// the same reason "This Is Me" is: neither is done more than once on a trip,
/// and a permanent affordance for either would sit in front of the balances for
/// the rest of the week.
///
/// Both fields sync — see `GroupStore.update(_:name:color:)`. They are what this
/// person *is* to everyone in the group rather than preferences of whoever
/// happens to be looking, and a name or colour that only moved on the phone that
/// changed it would make the same expense list read two ways.
///
/// Deliberately not a "remove member" sheet. Removing cascades into the expenses
/// they paid for, which is why it goes through the swipe and its confirmation
/// dialog on the list behind this — see `GroupDetailView.deletionMessage`. A
/// destructive action with that reach has no business one tap from a text field.
struct EditMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: PaletteColor
    /// `nil` means initials, which is the default and stays reachable from the
    /// grid — a member is not required to carry a glyph the way a group is.
    @State private var symbol: Emblem?

    /// Whether the current colour was picked rather than assigned, which is the
    /// only thing on this sheet there is to undo.
    private let wasChosen: Bool

    /// Called with the trimmed name and the chosen colour, or a `nil` colour to
    /// hand the member back to the roster's automatic assignment.
    private let onSave: (String, PaletteColor?, Emblem?) -> Void

    init(
        member: Person,
        avatar: PersonAvatar,
        onSave: @escaping (String, PaletteColor?, Emblem?) -> Void
    ) {
        _name = State(initialValue: member.name ?? "")
        // Seeded with what the row is already showing — which for a member
        // nobody has styled is the colour the roster gave them, not a blank.
        // Opening on the circle you just touched is the whole reason the
        // automatic assignment is stable.
        _color = State(initialValue: avatar.color)
        _symbol = State(initialValue: avatar.symbol)
        wasChosen = member.chosenColor != nil
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rebuilt from what is currently in the field rather than taken from the
    /// row, so the initials follow the typing. Correcting "Ana" to "Anna
    /// Kowalska" turns the circle from "A" into "AK" as you go, which is the
    /// only place the app ever explains where those letters come from.
    private var avatar: PersonAvatar {
        PersonAvatar(
            initials: PersonAvatar.initials(from: trimmedName),
            color: color,
            symbol: symbol
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The circle is the preview, at a size somebody can watch
                    // change. A swatch grid plus a separate sample of the result
                    // would be two ways of saying the same thing in one sheet.
                    HStack(spacing: 16) {
                        PersonIcon(avatar, size: 52)
                            .animation(.snappy, value: avatar)

                        TextField(String(localized: .memberName), text: $name)
                            .textContentType(.givenName)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    PaletteColorGrid(selection: $color)
                    EmblemGrid(selection: $symbol, tint: color)
                } footer: {
                    Text(.personalizationFooterInfo)
                }

                // Only once there is a choice to undo. A reset offered for a
                // colour nobody picked is a button that does nothing.
                if wasChosen {
                    Section {
                        // Carries the name out with it, so somebody who renamed
                        // *and* reset the colour doesn't silently lose the
                        // rename to whichever row they tapped last.
                        Button("Use Automatic Colour", role: .destructive) {
                            // The colour only. A symbol has no automatic
                            // assignment to fall back to — the way back from one
                            // is Initials, which is a tap in the grid above.
                            save(color: nil, symbol: symbol)
                        }
                        .disabled(trimmedName.isEmpty)
                    }
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save(color: PaletteColor?, symbol: Emblem?) {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, color, symbol)
        dismiss()
    }

    private func save() { save(color: color, symbol: symbol) }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            EditMemberSheet(
                member: PersistenceController.previewMember,
                avatar: PersonAvatar(initials: "AK", color: .teal)
            ) { name, color, symbol in
                print("save \(name) as \(String(describing: color)) \(String(describing: symbol))")
            }
        }
}
