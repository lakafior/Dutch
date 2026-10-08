/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import Foundation
import Testing

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    private func group(_ name: String, balance: Int? = nil) -> WidgetSnapshot.Group {
        WidgetSnapshot.Group(
            id: UUID(), name: name, currencyCode: "EUR", symbolName: "airplane", colorName: "teal",
            totalSpentCents: 10_000, myBalanceCents: balance, pendingTransfers: 2
        )
    }

    @Test("The last opened group leads, the rest keep list order")
    func lastOpenedLeads() {
        let a = group("A"), b = group("B"), c = group("C")
        let snapshot = WidgetSnapshot(groups: [a, b, c], lastOpenedGroupID: c.id)
        #expect(snapshot.ordered(limit: 3).map(\.name) == ["C", "A", "B"])
    }

    @Test("A last-opened id that matches no active group is ignored")
    func staleLastOpenedIgnored() {
        let a = group("A"), b = group("B")
        let snapshot = WidgetSnapshot(groups: [a, b], lastOpenedGroupID: UUID())
        #expect(snapshot.ordered(limit: 3).map(\.name) == ["A", "B"])
    }

    @Test("The limit caps the list, and zero shows nothing")
    func limit() {
        let snapshot = WidgetSnapshot(groups: [group("A"), group("B"), group("C")], lastOpenedGroupID: nil)
        #expect(snapshot.ordered(limit: 1).map(\.name) == ["A"])
        #expect(snapshot.ordered(limit: 0).isEmpty)
    }

    @Test("Round-trips through a file, balance and its absence included")
    func roundTrip() throws {
        let snapshot = WidgetSnapshot(groups: [group("Owes", balance: -4210), group("No identity")],
                                      lastOpenedGroupID: nil)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.write(to: url)
        let read = WidgetSnapshot.read(from: url)
        #expect(read == snapshot)
        #expect(read.groups[0].myBalance == Money(cents: -4210))
        #expect(read.groups[1].myBalance == nil)
    }

    @Test("A missing or unreadable file reads as empty instead of failing")
    func unreadableIsEmpty() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(WidgetSnapshot.read(from: missing) == .empty)

        let garbage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: garbage) }
        try Data("not json".utf8).write(to: garbage)
        #expect(WidgetSnapshot.read(from: garbage) == .empty)
    }
}
