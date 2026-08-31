/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

@Suite("Decimal field input")
struct DecimalInputTests {

    @Test("Reads a plain figure")
    func readsPlainFigure() {
        #expect(DecimalInput.parse("12.34") == 12.34)
        #expect(DecimalInput.parse("7") == 7)
    }

    /// The pad shows one separator and people type the other.
    @Test("Either decimal separator is accepted")
    func acceptsEitherSeparator() {
        #expect(DecimalInput.parse("12,34") == 12.34)
        #expect(DecimalInput.parse("12.34") == DecimalInput.parse("12,34"))
    }

    @Test("Surrounding whitespace is ignored")
    func ignoresWhitespace() {
        #expect(DecimalInput.parse("  12.34 ") == 12.34)
    }

    /// Blank, nonsense and zero are one case for every caller: nothing to act
    /// on yet, so leave the confirm button alone.
    @Test("Anything that is not a figure above zero fails")
    func rejectsNonFigures() {
        #expect(DecimalInput.parse("") == nil)
        #expect(DecimalInput.parse("   ") == nil)
        #expect(DecimalInput.parse("abc") == nil)
        #expect(DecimalInput.parse("0") == nil)
        #expect(DecimalInput.parse("0.00") == nil)
        #expect(DecimalInput.parse("-5") == nil)
    }

    @Test("Trailing zeros are dropped, so the field can be typed into")
    func dropsTrailingZeros() {
        #expect(DecimalInput.text(12, locale: .en) == "12")
        #expect(DecimalInput.text(12.50, locale: .en) == "12.5")
        #expect(DecimalInput.text(12.34, locale: .en) == "12.34")
    }

    @Test("Precision is a ceiling, and rates need more of it than amounts")
    func honoursPrecision() {
        #expect(DecimalInput.text(1.23456789, precision: 6, locale: .en) == "1.234568")
        #expect(DecimalInput.text(1.23456789, locale: .en) == "1.23")
    }

    /// The separator follows the device, and the parser reads both — which is
    /// the whole reason a Polish phone can prefill a field and read it back.
    @Test("The separator is the locale's")
    func usesLocaleSeparator() throws {
        let polish = DecimalInput.text(12.34, locale: Locale(identifier: "pl_PL"))
        #expect(polish == "12,34")
        #expect(DecimalInput.parse(polish) == 12.34)
    }

    /// The pairing is the point: a formatted figure has to survive being read
    /// back. Grouping separators are what breaks this, and four digits is
    /// where a locale starts inserting them.
    @Test("A formatted figure reads back as itself")
    func roundTrips() throws {
        for value in [4411.0, 1000.0, 12.34, 999999.99, 0.05] {
            for locale in [Locale.en, Locale(identifier: "pl_PL")] {
                let rendered = DecimalInput.text(value, locale: locale)
                let read = try #require(DecimalInput.parse(rendered))
                #expect(Money(amount: read) == Money(amount: value))
            }
        }
    }
}

private extension Locale {
    static let en = Locale(identifier: "en_US")
}
