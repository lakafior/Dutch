/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData

/// Wraps the expense the form is opening on, and what it is opening for, so it
/// can drive `sheet(item:)`.
///
/// `Expense` cannot be `Identifiable` off its own `id`: every attribute is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` id would never
/// present. The object id is always there, and is exactly as stable as the
/// object itself — and the mode joins it so that duplicating the row you just
/// finished editing counts as a different sheet rather than the same one again.
struct FormTarget: Identifiable {
    enum Mode: String {
        /// Rewrites the expense in place.
        case edit
        /// Leaves it alone and adds a copy.
        case duplicate
    }

    let expense: Expense
    let mode: Mode

    var id: String { "\(mode.rawValue)-\(expense.objectID.uriRepresentation())" }
}
