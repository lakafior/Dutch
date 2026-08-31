/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import SwiftUI

/// What a group looks like in a list: one symbol and one colour.
///
/// Purely decorative — nothing here is ever read to decide anything, and a group
/// with an appearance nobody recognises still splits money correctly. That is
/// what lets the stored values be plain strings that an older client can ignore.
struct GroupAppearance: Equatable {
    var symbol: Emblem
    var color: PaletteColor
}

// MARK: - Colour

/// The colours anything in the app can be tinted — groups here, people in
/// `PersonAvatar`.
///
/// Red and green are deliberately absent. Every row that carries a colour also
/// carries a balance, and the balance already spends both — red for what you
/// owe, green for what you are owed, see `Standing`. A group or a person tinted
/// either would make that figure a thing to double-check rather than read.
///
/// Stored by name rather than as a component triple, so restyling the palette
/// later restyles every group that already exists instead of freezing today's
/// RGB into everyone's database.
enum PaletteColor: String, CaseIterable, Identifiable {
    case blue, teal, indigo, purple, pink, orange, brown, gray

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .brown: .brown
        case .gray: .gray
        }
    }

    /// Named for VoiceOver, which otherwise has nothing at all to say about a
    /// grid of coloured circles.
    var label: LocalizedStringResource {
        switch self {
        case .blue: .colourBlue
        case .teal: .colourTeal
        case .indigo: .colourIndigo
        case .purple: .colourPurple
        case .pink: .colourPink
        case .orange: .colourOrange
        case .brown: .colourBrown
        case .gray: .colourGrey
        }
    }
}

// MARK: - Symbol

/// The symbols a group or a member can carry.
///
/// One set, shared, for the reason `PaletteColorGrid` is one grid: two curated
/// lists would drift into different glyphs, different translations and
/// different iOS floors while both claiming to be "the symbols you can pick".
/// It is named for neither owner because it belongs to both — a `Person` whose
/// emblem was typed `GroupSymbol` would read as a bug every time anybody
/// opened the file.
///
/// A fixed set rather than the whole SF Symbols catalogue. Six thousand symbols
/// need a search field, a results grid and an empty state — a lot of screen for
/// a decoration — and availability varies by OS version, so a freeform name
/// could arrive from a newer device and render as nothing. Two dozen fit in one
/// grid with no scrolling to speak of, and every one of them exists on iOS 17.
///
/// Ordered by theme, because that is how someone scanning for "the ski trip one"
/// looks for it.
///
/// Forty-eight of them, and the count is close to free to grow: the glyphs ship
/// with the OS, so a case costs a raw value, a switch arm and one localized
/// name. Going from twenty-four to forty-eight was measured on 2026-08-31 at
/// **1,549 bytes** — 32 of them in the binary and the rest in the two
/// `.strings` files, which is to say the cost of a symbol is its *name in two
/// languages* and nothing else. The archive did not move at all. Grow this list
/// when there is a reason to; the budget is not one.
/// Every case here existed by iOS 16, comfortably under the iOS 17 floor: a name
/// the running OS has never heard of renders as **nothing at all**, which is the
/// one failure mode this list has to rule out by construction rather than catch
/// at runtime.
enum Emblem: String, CaseIterable, Identifiable {
    // Getting there
    case airplane
    case car = "car.fill"
    case tram = "tram.fill"
    case ferry = "ferry.fill"
    case suitcase = "suitcase.fill"
    case map = "map.fill"

    // Outdoors
    case tent = "tent.fill"
    case beach = "beach.umbrella.fill"
    case mountains = "mountain.2.fill"
    case snow = "snowflake"
    case leaf = "leaf.fill"
    case paw = "pawprint.fill"

    // Home and everyday
    case house = "house.fill"
    case key = "key.fill"
    case cart = "cart.fill"
    case bag = "bag.fill"
    case bulb = "lightbulb.fill"
    case briefcase = "briefcase.fill"

    // Eating and going out
    case forkKnife = "fork.knife"
    case coffee = "cup.and.saucer.fill"
    case wine = "wineglass.fill"
    case cake = "birthday.cake.fill"
    case music = "music.note"
    case games = "gamecontroller.fill"

    // Creatures
    case hare = "hare.fill"
    case tortoise = "tortoise.fill"
    case bird = "bird.fill"
    case fish = "fish.fill"
    case ladybug = "ladybug.fill"
    case ant = "ant.fill"

    // Sky and elements
    case sun = "sun.max.fill"
    case moon = "moon.fill"
    case cloud = "cloud.fill"
    case flame = "flame.fill"
    case drop = "drop.fill"
    case sparkles

    // Doing things
    case walking = "figure.walk"
    case running = "figure.run"
    case bicycle
    case sports = "sportscourt.fill"
    case dumbbell = "dumbbell.fill"
    case guitar = "guitars.fill"

    // Things to have
    case camera = "camera.fill"
    case book = "book.fill"
    case heart = "heart.fill"
    case star = "star.fill"
    case crown = "crown.fill"
    case theatre = "theatermasks.fill"

    var id: String { rawValue }

    /// The SF Symbol name — the raw value is the name, which is what keeps the
    /// stored string meaningful to anything reading the database directly.
    var systemName: String { rawValue }

    /// Spelled out for VoiceOver. Without it the picker is two dozen buttons
    /// announced as "fork.knife", read one dotted component at a time.
    var label: LocalizedStringResource {
        switch self {
        case .airplane: .symbolPlane
        case .car: .symbolCar
        case .tram: .symbolTram
        case .ferry: .symbolFerry
        case .suitcase: .symbolSuitcase
        case .map: .symbolMap
        case .tent: .symbolTent
        case .beach: .symbolBeach
        case .mountains: .symbolMountains
        case .snow: .symbolSnow
        case .leaf: .symbolLeaf
        case .paw: .symbolPawPrint
        case .house: .symbolHouse
        case .key: .symbolKey
        case .cart: .symbolShoppingCart
        case .bag: .symbolBag
        case .bulb: .symbolLightbulb
        case .briefcase: .symbolBriefcase
        case .forkKnife: .symbolRestaurant
        case .coffee: .symbolCoffee
        case .wine: .symbolWine
        case .cake: .symbolCake
        case .music: .symbolMusic
        case .games: .symbolGames
        case .hare: .symbolHare
        case .tortoise: .symbolTortoise
        case .bird: .symbolBird
        case .fish: .symbolFish
        case .ladybug: .symbolLadybug
        case .ant: .symbolAnt
        case .sun: .symbolSun
        case .moon: .symbolMoon
        case .cloud: .symbolCloud
        case .flame: .symbolFlame
        case .drop: .symbolDrop
        case .sparkles: .symbolSparkles
        case .walking: .symbolWalking
        case .running: .symbolRunning
        case .bicycle: .symbolBicycle
        case .sports: .symbolSports
        case .dumbbell: .symbolDumbbell
        case .guitar: .symbolGuitar
        case .camera: .symbolCamera
        case .book: .symbolBook
        case .heart: .symbolHeart
        case .star: .symbolStar
        case .crown: .symbolCrown
        case .theatre: .symbolTheatre
        }
    }
}

// MARK: - Derivation

extension GroupAppearance {
    /// The look a group falls back to when it has never been given one.
    ///
    /// Derived from the group's own id, so every group that existed before this
    /// feature did becomes distinct the moment the app updates — with no
    /// migration to write, nothing to sync, and no "pick an icon" chore standing
    /// between the user and a list they can already read.
    ///
    /// It has to be the *bytes* of the UUID, not `hashValue`: Swift seeds its
    /// hasher per process, so a hash-derived icon would change colour on every
    /// launch and differ between two phones looking at the same shared group.
    static func derived(from id: UUID?) -> GroupAppearance {
        guard let id else {
            // A record too incomplete to have an id is half-synced and about to
            // change anyway; anything stable will do.
            return GroupAppearance(symbol: .forkKnife, color: .blue)
        }

        // Two independent sums over alternating bytes, so the colour and the
        // symbol don't march in lockstep — folding one number would tie teal to
        // the same handful of glyphs forever.
        let (symbolSeed, colorSeed) = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.enumerated().reduce(into: (UInt64(0), UInt64(0))) { seeds, byte in
                if byte.offset.isMultiple(of: 2) {
                    seeds.0 &+= UInt64(byte.element)
                } else {
                    seeds.1 &+= UInt64(byte.element)
                }
            }
        }

        return GroupAppearance(
            symbol: Emblem.allCases[Int(symbolSeed % UInt64(Emblem.allCases.count))],
            color: PaletteColor.allCases[Int(colorSeed % UInt64(PaletteColor.allCases.count))]
        )
    }

    /// A look for a group that doesn't exist yet, so the new-group sheet opens
    /// on something with a bit of personality and two groups made in a row don't
    /// arrive as twins.
    static var random: GroupAppearance {
        GroupAppearance(
            symbol: Emblem.allCases.randomElement() ?? .forkKnife,
            color: PaletteColor.allCases.randomElement() ?? .blue
        )
    }
}

// MARK: - Archive

extension ExpenseGroup {
    /// Whether this group has been put away.
    ///
    /// A `Date` in the model rather than a `Bool`, for nothing this build uses:
    /// *when* a trip ended is the sort key an archive screen would eventually
    /// want, and a boolean cannot be widened into one later without a second
    /// model version and a second CloudKit promote. The attribute is free
    /// either way — this is the cheap half of a decision whose expensive half
    /// is irreversible.
    ///
    /// Nothing about the money changes. An archived group still settles, still
    /// syncs, and still counts against `GroupLimit` — see the note there.
    var isArchived: Bool { archivedDate != nil }
}

// MARK: - Group

extension ExpenseGroup {
    /// How this group renders.
    ///
    /// The stored attributes are an override, not the source: an unset — or
    /// unrecognised — name falls back to the derived look rather than to a
    /// placeholder. Unrecognised matters, because a future version of the app
    /// may add a symbol this one has never heard of and sync it down here.
    var appearance: GroupAppearance {
        let derived = GroupAppearance.derived(from: id)
        return GroupAppearance(
            symbol: symbolName.flatMap(Emblem.init(rawValue:)) ?? derived.symbol,
            color: colorName.flatMap(PaletteColor.init(rawValue:)) ?? derived.color
        )
    }
}
