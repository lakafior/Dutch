/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// The tint of the group being looked at, so a row deep in the hierarchy can
/// carry it without every intermediate view passing it down.
///
/// Defaults to `.accentColor`, which is what a preview or a stray call site
/// gets — never a hardcoded blue that would silently disagree with a group.
struct ExpenseGroupTintKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var expenseGroupTint: Color {
        get { self[ExpenseGroupTintKey.self] }
        set { self[ExpenseGroupTintKey.self] = newValue }
    }
}
