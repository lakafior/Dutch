/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Counts as words. The agreement lives in the string catalog rather than
/// here: English needs two forms, Polish needs four, and a `singular`/
/// `plural` pair in Swift can only ever express the first of those.
///
/// Shared rather than duplicated per view. Both the summary block and the
/// member-deletion warning count the same things, and two copies of this is
/// two places for a plural rule to drift.
enum ItemCount {
    static func expenses(_ value: Int) -> String {
        String(localized: "\(value) expenses")
    }

    static func members(_ value: Int) -> String {
        String(localized: "\(value) members")
    }
}
