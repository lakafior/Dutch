/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// The currency list, as a screen of its own rather than a `Picker`.
///
/// `.pickerStyle(.navigationLink)` pushes a list that cannot be searched, and
/// this one is ~150 rows: reaching HUF meant scrolling past a hundred codes
/// nobody on the trip will ever spend. Search is the entire reason this is
/// hand-rolled, and it matches the localized name as readily as the code —
/// somebody hunting for forint does not necessarily know it is HUF.
///
/// A file of its own rather than a fourth private type at the foot of
/// `ExpenseFormView`: it shares no state with the form beyond the binding, and
/// the form is the one file in this app already carrying a comment about the
/// type checker's limits.
struct CurrencyPicker: View {
    @Binding var selection: String
    /// The group's own currency, the selection, and whatever this trip has
    /// already spent in — see `ExpenseFormView.inUseCurrencies`.
    let inUse: [String]
    let all: [String]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List {
            let used = matches(inUse)
            if !used.isEmpty {
                Section("Used in This Group") {
                    ForEach(used, id: \.self, content: row)
                }
            }

            // The full list stays full, including the codes repeated above.
            // Filtering them out would make the alphabet skip entries for
            // reasons invisible to somebody scrolling it, and a duplicated tick
            // in two sections is the ordinary shape of a suggestions list.
            Section("All Currencies") {
                ForEach(matches(all), id: \.self, content: row)
            }
        }
        .searchable(text: $query, prompt: "Code or name")
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A row, not a `Picker` tag: choosing a currency should close the screen
    /// the way a picker's own list does, and a plain selection binding would
    /// leave the user to find Back for themselves.
    private func row(_ code: String) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(Self.label(code))
                    .foregroundStyle(.primary)

                Spacer(minLength: 12)

                if code == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        // The trait below says this to VoiceOver already.
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(code == selection ? [.isSelected] : [])
    }

    /// Matches on the whole label, so "zloty", "PLN" and "Polish" all find the
    /// same row.
    private func matches(_ codes: [String]) -> [String] {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return codes }

        return codes.filter {
            Self.label($0).localizedCaseInsensitiveContains(term)
        }
    }

    // MARK: - Names

    /// Built once — `commonISOCurrencyCodes` is ~150 entries and looking up a
    /// localized name per row per render would redo that work on every
    /// keystroke in the search field.
    private static let names: [String: String] = {
        let locale = Locale.current
        return Dictionary(
            uniqueKeysWithValues: Locale.commonISOCurrencyCodes.compactMap { code in
                locale.localizedString(forCurrencyCode: code).map { (code, $0) }
            }
        )
    }()

    private static func label(_ code: String) -> String {
        guard let name = names[code] else { return code }
        return "\(code) · \(name)"
    }
}
