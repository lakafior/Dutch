/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Testing
@testable import DutchKit

@Suite("RegionCurrency")
struct RegionCurrencyTests {

    /// The seven the roadmap named, because they are the trip this feature was
    /// described for: a drive through central Europe, and the two long-haul
    /// destinations whose currencies have no minor unit.
    @Test("Reads the currency out of ICU rather than a table", arguments: [
        ("PL", "PLN"), ("NL", "EUR"), ("JP", "JPY"), ("GB", "GBP"),
        ("CH", "CHF"), ("HU", "HUF"), ("CZ", "CZK"), ("US", "USD"),
    ])
    func knownRegions(region: String, currency: String) {
        #expect(RegionCurrency.code(for: region) == currency)
    }

    @Test("Accepts the case and padding a placemark might arrive with")
    func normalisation() {
        #expect(RegionCurrency.code(for: "pl") == "PLN")
        #expect(RegionCurrency.code(for: " de ") == "EUR")
    }

    /// The `nil`s matter more than the hits: each one is a case where the form
    /// has to leave the currency alone, and a lookup that invented an answer
    /// here would switch somebody's expense into a currency they never went to.
    @Test("Nothing plausible comes back for a code that isn't a country")
    func unknownRegions() {
        #expect(RegionCurrency.code(for: "") == nil)
        #expect(RegionCurrency.code(for: "XYZZY") == nil)
        #expect(RegionCurrency.code(for: "P1") == nil)
        #expect(RegionCurrency.code(for: "Polska") == nil)
    }

    /// Antarctica is a country code with no currency behind it. It is also the
    /// case that proves the type reads ICU rather than guessing: a hand-written
    /// table would have had to remember to leave it out.
    @Test("A region with no currency answers nil, not a guess")
    func regionWithoutCurrency() {
        #expect(RegionCurrency.code(for: "AQ") == nil)
    }
}
