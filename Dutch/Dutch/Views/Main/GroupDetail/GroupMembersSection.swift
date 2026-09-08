/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// The roster, with each member's balance and the menu that renames them or
/// claims one as this device's owner.
struct GroupMembersSection: View {
    let contents: GroupContents
    let currencyCode: String
    /// Which member is the person holding this phone, or `nil` if they haven't
    /// said.
    let me: Person?
    /// People on the share who aren't linked to a member yet.
    let unclaimedJoiners: [String]
    let onEdit: (Person, PersonAvatar) -> Void
    let onSetIdentity: (Person?) -> Void
    let onDelete: ([Person]) -> Void
    let onAdd: () -> Void

    var body: some View {
        Section {
            // No placeholder row while this is empty. The header says what the
            // section is and the button below says what to do about it, so a
            // third line saying the same thing was the redundancy people
            // reported. `expensesSection` already works this way — a
            // placeholder *or* an action, never both — and this was the one
            // section that stacked the two.
            //
            // The header is what stays. Making it read "Add Members" while
            // empty is the other obvious fix and is worse: a section header is
            // what VoiceOver announces before every row beneath it, so a verb
            // there is read out immediately before the button that repeats it.
            ForEach(contents.members, id: \.objectID) { member in
                MemberBalanceRow(
                    name: member.name ?? String(localized: .unnamedMember),
                    avatar: contents.avatars[member],
                    isLinked: member.cloudUserRecordName != nil,
                    balance: member.id.flatMap { contents.balances[$0] },
                    currencyCode: currencyCode,
                    isMe: member == me
                )
                // A context menu rather than a row of its own: identity is
                // set once and never thought about again, and a permanent
                // "who am I" control would sit in the way of the balances
                // for the rest of the trip. Renaming and recolouring are
                // here for the same reason, and above the identity items
                // because they apply to every row — including the ones
                // already claimed by somebody else.
                .contextMenu {
                    Button("Edit Member", systemImage: "pencil") {
                        onEdit(member, contents.avatars[member])
                    }

                    if member == me {
                        Button("Not Me", systemImage: "person.slash") {
                            onSetIdentity(nil)
                        }
                    } else if CloudIdentity.isSomeoneElse(member) {
                        // Offered as a disabled row rather than hidden, so
                        // the answer to "why can't I pick this one?" is on
                        // screen instead of being an unexplained gap in a
                        // menu every other row has.
                        Button("Already Someone Else", systemImage: "person.fill.xmark") {}
                            .disabled(true)
                    } else {
                        Button("This Is Me", systemImage: "person.crop.circle.badge.checkmark") {
                            onSetIdentity(member)
                        }
                    }
                }
            }
            .onDelete { offsets in
                onDelete(offsets.map { contents.members[$0] })
            }

            // A full-width row, not a glyph in the section header. This is the
            // only way to make the app usable on first launch, and a header
            // button gave it a ~20pt target well under the 44pt minimum.
            Button(action: onAdd) {
                Label("Add Member", systemImage: "person.badge.plus")
            }
        } header: {
            Text(.members)
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                // Shown only until it has been answered — a hint that stays on
                // screen after you've acted on it is just clutter.
                if me == nil, !contents.members.isEmpty {
                    Text(.addressingTip)
                }

                // The roster looks complete whether or not it is, so the only
                // sign that somebody joined and never picked a name is this.
                if !unclaimedJoiners.isEmpty {
                    Text(unclaimedJoinersMessage)
                }
            }
        }
    }

    /// "Ala and Bartek have joined but haven't picked a name yet."
    ///
    /// They/their throughout: CloudKit hands over a name, never a pronoun, and
    /// guessing one from a name gets it wrong for real people.
    private var unclaimedJoinersMessage: String {
        let names = unclaimedJoiners.formatted(.list(type: .and))
        return unclaimedJoiners.count == 1
            ? String(
                localized: "\(names) has joined but hasn't picked their name from this list yet.",
                comment: "Footer under the member list. The placeholder is one name."
            )
            : String(
                localized: "\(names) have joined but haven't picked their names from this list yet.",
                comment: "Footer under the member list. The placeholder is a formatted list of names."
            )
    }
}
