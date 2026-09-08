/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreTransferable
import DutchKit

/// The group summary as something `ShareLink` can hand to the share sheet.
///
/// A `Transferable` wrapper rather than the finished `String`, because
/// `ShareLink` takes its item eagerly: passing the text itself would build the
/// whole message — a line per expense, formatted — on every redraw of this
/// screen, for a button most people tap once a trip. `ProxyRepresentation`
/// defers that to the tap.
///
/// Deferring is only safe because `GroupSummary` is a value snapshot with no
/// managed objects in it, so the closure can run whenever and on whatever actor
/// the share sheet chooses. Capturing anything Core Data owns here would be a
/// crash waiting for a slow share sheet.
struct SharedSummary: Transferable {
    let summary: GroupSummary

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { $0.summary.text(strings: .localized) }
    }
}
