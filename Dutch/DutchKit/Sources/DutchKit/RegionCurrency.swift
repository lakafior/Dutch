/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// What a country spends, from an ISO 3166 country code.
///
/// A four-line type with a long comment, because the interesting part is the
/// thing it *doesn't* do: there is no table here, and there must never be one.
/// ICU ships the country-to-currency mapping inside the OS, and Foundation
/// exposes it through a locale built from nothing but a region —
/// `und_PL`, an undetermined language spoken in Poland — whose `currency` is
/// `PLN`. An embedded currency database is one of the few things named in the
/// roadmap as a genuine risk to this app's size budget, and this feature does
/// not need one.
///
/// In DutchKit rather than beside the view that uses it because it needs
/// neither MapKit nor a simulator to be true: the input is a two-letter string
/// and the output is a two-letter string.
public enum RegionCurrency {
    /// The ISO 4217 currency for a region, or `nil` where there isn't one.
    ///
    /// `nil` is a real answer and the call site must respect it. Antarctica has
    /// no currency, a malformed code has no country, and in both cases the
    /// honest behaviour is to leave the expense in whatever currency it was
    /// already going to be — never to fall back on the device's region setting,
    /// which is exactly the wrong answer for somebody abroad.
    public static func code(for regionCode: String) -> String? {
        let region = regionCode.trimmingCharacters(in: .whitespaces).uppercased()

        // Two ASCII letters. `Locale(identifier:)` accepts nearly anything and
        // quietly invents an answer for the rest — "und_XYZZY" is a locale as
        // far as it is concerned — so the guard is what keeps a typo from
        // becoming a currency.
        guard region.count == 2, region.allSatisfy({ $0.isLetter && $0.isASCII }) else {
            return nil
        }

        guard let code = Locale(identifier: "und_\(region)").currency?.identifier else {
            return nil
        }

        // ICU answers a region with no currency of its own with `XXX`, the ISO
        // 4217 code that *means* "no currency" — Antarctica returns it. Passed
        // through, it would set an expense's currency to a code no bank has
        // ever quoted a rate for, which is worse than leaving it alone, and it
        // looks like a real answer at every layer above this one. `XTS` is the
        // same trap wearing a test label.
        return Self.placeholders.contains(code) ? nil : code
    }

    private static let placeholders: Set<String> = ["XXX", "XTS"]
}
