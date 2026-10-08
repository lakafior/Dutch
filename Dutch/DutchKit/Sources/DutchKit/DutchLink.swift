/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// A place in the app that something outside it — the Home Screen widget — can
/// open by URL.
///
/// Built and parsed in one type so the widget and the app cannot disagree about
/// the format: the widget writes `url`, the app reads `init?(url:)`, and a
/// round trip is a test rather than a hope.
///
/// Navigation only, never an action. Any app or web page can open a custom URL
/// scheme, so a link here may name where to go but must never do anything on
/// arrival — the worst a forged link can achieve is opening a group's screen, or
/// a form the person then has to fill in and save themselves.
public enum DutchLink: Equatable, Sendable {
    /// A group's detail screen.
    case group(UUID)
    /// The new-expense form, in a group or — without one — the last opened.
    case newExpense(UUID?)

    /// Registered in `Dutch-Info.plist`. Reverse-DNS rather than a bare `dutch`,
    /// which another app could plausibly claim too — and iOS picks between two
    /// apps claiming one scheme without saying which.
    public static let scheme = "net.smigi.dutch"

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = Self.scheme
        switch self {
        case .group(let id):
            parts.host = "group"
            parts.path = "/" + id.uuidString
        case .newExpense(let id):
            parts.host = "new-expense"
            if let id { parts.path = "/" + id.uuidString }
        }
        return parts.url!
    }

    /// `nil` for anything that isn't a well-formed link of this app's, which is
    /// the only safe answer to a URL that could have come from anywhere.
    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let id = url.pathComponents.dropFirst().first.flatMap(UUID.init(uuidString:))
        switch url.host?.lowercased() {
        case "group":
            guard let id else { return nil }
            self = .group(id)
        case "new-expense":
            // A path that is present but isn't a UUID is malformed, not "no group".
            if url.pathComponents.count > 1, id == nil { return nil }
            self = .newExpense(id)
        default:
            return nil
        }
    }
}
