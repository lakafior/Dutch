/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import Testing
@testable import Dutch

/// Covers the part of a group's look that has to hold still: a group nobody
/// styled must render the same symbol and colour on every launch and on every
/// device, or the icon stops being a way to recognise it.
@MainActor
@Suite("Group appearance")
struct GroupAppearanceTests {

    // MARK: - Derivation

    @Test("The same id always derives the same look")
    func derivationIsStable() {
        let id = UUID()
        #expect(GroupAppearance.derived(from: id) == GroupAppearance.derived(from: id))
    }

    /// The regression this guards is `hashValue`: Swift seeds its hasher per
    /// process, so a hash-derived icon would be stable within one launch and
    /// change on the next — which is exactly what this test would not catch if
    /// it only compared two calls in a row. Fixed bytes, fixed answer.
    @Test("Derivation reads the id's bytes, not a per-process hash")
    func derivationIsSeedIndependent() throws {
        let id = try #require(UUID(uuidString: "6E9F2C1A-4B3D-4E5F-8A7B-0C1D2E3F4A5B"))
        let appearance = GroupAppearance.derived(from: id)

        // Byte sums: even offsets pick the symbol, odd ones the colour.
        // 6E + 2C + 4B + 4E + 8A + 0C + 2E + 4A = 577
        // 9F + 1A + 3D + 5F + 7B + 1D + 3F + 5B = 647
        let expectedSymbol = Emblem.allCases[577 % Emblem.allCases.count]
        let expectedColor = PaletteColor.allCases[647 % PaletteColor.allCases.count]

        #expect(appearance.symbol == expectedSymbol)
        #expect(appearance.color == expectedColor)
    }

    /// 500 draws, not 100: covering all 24 symbols is a coupon-collector
    /// problem with an expectation near 90, and a sample sized to the average
    /// misses one often enough to make the suite flaky.
    @Test("Different ids spread across the palette")
    func derivationVaries() {
        let looks = (0..<500).map { _ in GroupAppearance.derived(from: UUID()) }

        #expect(Set(looks.map(\.color)).count == PaletteColor.allCases.count)
        #expect(Set(looks.map(\.symbol)).count == Emblem.allCases.count)
    }

    @Test("A record with no id still has a look")
    func derivationHandlesMissingID() {
        #expect(GroupAppearance.derived(from: nil) == GroupAppearance.derived(from: nil))
    }

    // MARK: - Storage

    @Test("A group created without a choice falls back to its derived look")
    func unstyledGroupUsesDerivedLook() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")

        #expect(group.symbolName == nil)
        #expect(group.colorName == nil)
        #expect(group.appearance == GroupAppearance.derived(from: group.id))
    }

    @Test("A chosen look is stored and read back")
    func chosenLookRoundTrips() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let chosen = GroupAppearance(symbol: .mountains, color: .teal)
        let group = try store.createGroup(named: "Ski", appearance: chosen)

        #expect(group.symbolName == "mountain.2.fill")
        #expect(group.colorName == "teal")
        #expect(group.appearance == chosen)
    }

    @Test("Editing rewrites the name and the look together")
    func updateRewritesNameAndLook() throws {
        let store = GroupStore(context: TestStack.makeContext())
        let group = try store.createGroup(named: "Trip")

        try store.update(group, name: "Kraków", appearance: GroupAppearance(symbol: .wine, color: .pink))

        #expect(group.name == "Kraków")
        #expect(group.appearance == GroupAppearance(symbol: .wine, color: .pink))
    }

    /// A newer version of the app may add a symbol this one has never heard of
    /// and sync it down. Falling back to the derived look keeps the row drawing
    /// something recognisable instead of an empty tile.
    @Test("An unrecognised stored name falls back rather than rendering nothing")
    func unknownNamesFallBack() throws {
        let context = TestStack.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")

        group.symbolName = "sailboat.circle.fill"
        group.colorName = "chartreuse"

        #expect(group.appearance == GroupAppearance.derived(from: group.id))
    }
}
