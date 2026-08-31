/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// Sheet for renaming a group, changing how it looks, and putting it away.
///
/// Deliberately not a currency editor. The currency is pinned when the group is
/// created because every amount recorded since has been *in* it — switching it
/// later wouldn't convert anything, it would silently reinterpret nine months of
/// receipts as if they had been paid in the new one. The footer says so, since a
/// missing control with no explanation reads as an oversight.
struct EditGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var appearance: GroupAppearance

    /// Called with the trimmed name and the chosen look.
    private let onSave: (String, GroupAppearance) -> Void
    /// Called with the new archived state. Separate from `onSave` because it is
    /// the one control here that changes what the group *is* rather than how it
    /// looks, and because it dismisses on its own.
    private let onSetArchived: (Bool) -> Void
    private let currencyCode: String
    private let isArchived: Bool

    init(
        group: ExpenseGroup,
        onSave: @escaping (String, GroupAppearance) -> Void,
        onSetArchived: @escaping (Bool) -> Void
    ) {
        _name = State(initialValue: group.name ?? "")
        // Seeded with what the row is already showing — which for a group that
        // has never been styled is its derived look, not a blank. Opening the
        // sheet on the icon you were just looking at is the whole reason the
        // derivation is stable.
        _appearance = State(initialValue: group.appearance)
        self.currencyCode = group.currency
        self.isArchived = group.isArchived
        self.onSave = onSave
        self.onSetArchived = onSetArchived
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        GroupIcon(appearance)

                        TextField("Group Name", text: $name)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                } footer: {
                    Text("Recorded in \(currencyCode), fixed when the group was created.")
                }

                Section("Appearance") {
                    AppearancePicker(appearance: $appearance)
                }

                // The findable way to archive, and the reason this sheet is no
                // longer only about how a group looks.
                //
                // The swipe on the list came first and was the whole of it,
                // which was the same mistake this codebase already has a
                // comment about on `TransferRow`: a gesture with no affordance
                // is a feature most people never find. Somebody finishing with
                // a trip opens the group and looks for a control; this is where
                // they look.
                //
                // Not `.destructive`. Archiving destroys nothing, every expense
                // stays, and one tap in the same place brings it back — red
                // here would read as the delete this deliberately is not.
                Section {
                    Button {
                        onSetArchived(!isArchived)
                        dismiss()
                    } label: {
                        if isArchived {
                            Label("Unarchive Group", systemImage: "tray.and.arrow.up")
                        } else {
                            Label("Archive Group", systemImage: "archivebox")
                        }
                    }
                } footer: {
                    Text(isArchived ? .unarchiveExplanation : .archiveExplanation)
                }
            }
            .navigationTitle("Edit Group")
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

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, appearance)
        dismiss()
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            EditGroupSheet(
                group: PersistenceController.previewGroup,
                onSave: { name, appearance in print("save \(name) as \(appearance)") },
                onSetArchived: { print("archived \($0)") }
            )
        }
}
