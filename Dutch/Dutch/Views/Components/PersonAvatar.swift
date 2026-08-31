/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import Foundation

/// What a person looks like in a list: their initials on one colour.
///
/// Nothing is stored. The initials come from the name that is already there and
/// the colour from the id that is already there, so this cost no Core Data
/// version, no CloudKit schema promotion, and no bytes in anyone's database —
/// and it lights up every group that existed before it did.
///
/// It is also the whole answer to profile photos. An avatar people can set is a
/// picker, a downscaler, a `CKAsset` per member syncing through a shared zone,
/// and a reason to ask for the photo library; deriving one asks for nothing.
/// See `GroupAppearance` for the same trade made for groups.
struct PersonAvatar: Equatable {
    /// One or two characters, or `nil` when the name yields nothing worth
    /// drawing — which `PersonIcon` answers with a glyph rather than a stray
    /// "?" that reads like an error.
    var initials: String?
    var color: PaletteColor
    /// A symbol the member picked, drawn *instead of* their initials.
    ///
    /// Nil for everybody until they choose one, which is what keeps the derived
    /// avatar the default: initials from a name that is already there beat a
    /// glyph nobody asked for, and a roster of identical `person.fill` circles
    /// would be worse than what this replaced.
    var symbol: Emblem?
}

// MARK: - Initials

extension PersonAvatar {
    /// Cached, per the rest of the app: a formatter per row is the expensive
    /// way to do this, and these are built inside a `ForEach`.
    ///
    /// `@MainActor` because `PersonNameComponentsFormatter` is a mutable class
    /// with no thread-safety guarantee, and every caller is a view body anyway.
    @MainActor
    private static let nameFormatter: PersonNameComponentsFormatter = {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .abbreviated
        return formatter
    }()

    /// The initials to draw for a name.
    ///
    /// Parsed rather than split on spaces. `PersonNameComponentsFormatter` knows
    /// that "山田太郎" leads with the family name and that "van der Berg" is one
    /// surname, where `split(separator: " ").map(\.first)` produces "山" and
    /// "vdB" respectively.
    ///
    /// Capped at two characters because the circle is 30pt wide: a name that
    /// parses into three or more initials would be drawn as a smudge.
    @MainActor
    static func initials(from name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }

        if let components = nameFormatter.personNameComponents(from: trimmed) {
            let abbreviated = nameFormatter.string(from: components)
            if !abbreviated.isEmpty {
                return String(abbreviated.prefix(2))
            }
        }

        // Names the formatter declines to parse still have a first character,
        // and one letter beats an empty circle. `localizedUppercase` because
        // Turkish dotless i uppercases to a different letter than ASCII rules
        // would give.
        return String(trimmed.prefix(1)).localizedUppercase
    }
}

// MARK: - Colour

extension PaletteColor {
    /// The colour an id falls to when nothing else is competing for it.
    ///
    /// The *bytes* of the UUID, never `hashValue` — Swift seeds its hasher per
    /// process, so a hash-derived colour would change on every launch and two
    /// phones looking at the same shared group would disagree. Same reasoning,
    /// and the same trap, as `GroupAppearance.derived(from:)`.
    static func derived(from id: UUID?) -> PaletteColor {
        guard let id else {
            // A member too incomplete to have an id is half-synced and about to
            // change anyway; anything stable will do.
            return .blue
        }

        let sum = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(0)) { $0 &+ UInt64($1) }
        }
        return allCases[Int(sum % UInt64(allCases.count))]
    }

}

// MARK: - Chosen colour

extension Person {
    /// The colour somebody picked for this member, if anybody did.
    ///
    /// An override rather than the source, exactly as `ExpenseGroup.appearance`
    /// is: unset — or a name a newer version of the app invented and synced down
    /// here — falls through to the roster's own assignment rather than to a
    /// placeholder. Stored by name for the same reason the group's is, so
    /// restyling the palette restyles everyone who already picked from it.
    var chosenColor: PaletteColor? {
        get { colorName.flatMap(PaletteColor.init(rawValue:)) }
        set { colorName = newValue?.rawValue }
    }

    /// The symbol somebody picked for this member, if anybody did.
    ///
    /// Same contract as `chosenColor`: an override rather than a source, and a
    /// name this build has never heard of — invented by a newer version and
    /// synced down here — falls through to `nil` and the initials, rather than
    /// drawing the empty square an unknown SF Symbol renders as.
    var chosenSymbol: Emblem? {
        get { symbolName.flatMap(Emblem.init(rawValue:)) }
        set { symbolName = newValue?.rawValue }
    }
}

// MARK: - Roster

/// The avatars for one group's members, assigned so that no two of them share a
/// colour.
///
/// Deriving each person's colour from their own id alone would have been a line
/// of code, and wrong in the common case: eight colours over four people leaves
/// a better-than-even chance that two of them come out the same, which is the
/// one thing a colour meant to tell people apart must not do. So the roster is
/// resolved together — each member takes their derived colour if it is free and
/// the next free one if it isn't.
///
/// Built once per screen and subscripted per row, because the assignment is a
/// pass over the whole roster and doing that inside a `ForEach` would make it
/// quadratic.
@MainActor
struct RosterAvatars {
    private var colors: [NSManagedObjectID: PaletteColor] = [:]

    init(_ members: [Person]) {
        // Ordered by id, not by the name the roster arrives sorted under.
        // Ordering by name means renaming one person reshuffles the colours of
        // everyone who sorts after them, and two devices whose locales collate
        // differently would draw the same group two ways.
        let ordered = members.sorted { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        let palette = PaletteColor.allCases

        // Two passes, and the order between them is the whole point. A colour
        // somebody picked is placed before anything is derived, so it is the
        // automatic neighbours that move out of the way — one pass would let
        // whoever came first in the walk take a colour another member had
        // explicitly asked for, and the person who chose it would watch their
        // circle change because somebody else joined the group.
        var taken: Set<PaletteColor> = []
        for member in ordered {
            // Two members who both chose teal both get teal. That is what they
            // asked for, and second-guessing it would mean the picker sometimes
            // doesn't do what it says.
            guard let chosen = member.chosenColor else { continue }
            colors[member.objectID] = chosen
            taken.insert(chosen)
        }

        for member in ordered where colors[member.objectID] == nil {
            // Past the end of the palette the cycle starts over. A group of
            // more than eight is already past the point where colour is doing
            // much work, and repeating beats handing everyone after the eighth
            // the same grey.
            if taken.count == palette.count { taken.removeAll() }

            // Their own colour if it is free, otherwise the next one round the
            // palette. Walking forward rather than taking any free colour is
            // what keeps this reproducible: every device runs the same walk
            // over the same order and lands on the same answer.
            let start = palette.firstIndex(of: .derived(from: member.id)) ?? 0
            let color = palette.indices
                .lazy
                .map { palette[(start + $0) % palette.count] }
                .first { !taken.contains($0) } ?? palette[start]

            colors[member.objectID] = color
            taken.insert(color)
        }
    }

    /// The avatar for a member. A person who wasn't in the roster this was built
    /// from still gets their own colour rather than nothing, so a row that
    /// arrives mid-sync draws correctly instead of blank.
    subscript(member: Person) -> PersonAvatar {
        PersonAvatar(
            initials: PersonAvatar.initials(from: member.name),
            color: colors[member.objectID] ?? member.chosenColor ?? .derived(from: member.id),
            symbol: member.chosenSymbol
        )
    }
}
