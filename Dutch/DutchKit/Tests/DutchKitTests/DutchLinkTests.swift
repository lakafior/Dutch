/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import Foundation
import Testing

@Suite("Dutch links")
struct DutchLinkTests {
    @Test("Every link survives a round trip through its URL", arguments: [
        DutchLink.group(UUID()), .newExpense(UUID()), .newExpense(nil),
    ])
    func roundTrip(link: DutchLink) {
        #expect(DutchLink(url: link.url) == link)
    }

    @Test("The URL uses the registered scheme")
    func scheme() {
        #expect(DutchLink.newExpense(nil).url.absoluteString == "net.smigi.dutch://new-expense")
    }

    @Test("Foreign and malformed URLs are refused", arguments: [
        "https://dutch.smigi.net/group/\(UUID().uuidString)",
        "net.smigi.dutch://group",
        "net.smigi.dutch://group/not-a-uuid",
        "net.smigi.dutch://new-expense/not-a-uuid",
        "net.smigi.dutch://delete/\(UUID().uuidString)",
    ])
    func refused(string: String) throws {
        #expect(DutchLink(url: try #require(URL(string: string))) == nil)
    }
}
