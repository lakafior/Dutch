/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import SwiftUI

/// What an expense was for.
///
/// A fixed set rather than free text, for the reason `Emblem` is a fixed
/// set: freeform names need a search field and an empty state, and two people
/// in the same group would file the same dinner under "Food" and "food" and
/// never see each other's. Twelve fit one menu without scrolling.
///
/// Unlike a group's symbol this is **not** decorative — a category has a name
/// the user reads, so each case carries a localized label shown as text rather
/// than only announced to VoiceOver. The raw value is still the SF Symbol name,
/// which keeps the stored string meaningful to anything reading the database
/// directly and keeps the storage identical in shape to the group's.
///
/// Deliberately not a balance input. Nothing in `SettlementBridge` reads this,
/// and an expense whose category a newer version of the app invented still
/// splits correctly here — see `Expense.category`, which falls back to `nil`
/// rather than to a placeholder.
///
/// `Comparable` only so `SpendBreakdown` has a decided tie-break when two
/// categories come to the same figure. Ordering by raw value is arbitrary as
/// *meaning*, and that is fine — its whole job is to be the same answer twice,
/// so a chart of equal bars does not reshuffle between redraws.
enum ExpenseCategory: String, CaseIterable, Identifiable, Comparable {
    static func < (lhs: ExpenseCategory, rhs: ExpenseCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    case dining = "fork.knife"
    case groceries = "cart.fill"
    case drinks = "wineglass.fill"
    case transport = "car.fill"
    case flights = "airplane"
    case accommodation = "bed.double.fill"
    case entertainment = "ticket.fill"
    case shopping = "bag.fill"
    case bills = "bolt.fill"
    case health = "cross.case.fill"
    case gifts = "gift.fill"
    case other = "tag.fill"

    var id: String { rawValue }

    /// The SF Symbol name. Every one of these has existed since well before
    /// iOS 17, which is the floor a stored name has to clear: a symbol the
    /// running OS has never heard of renders as nothing at all, and a category
    /// drawn as a gap is worse than one drawn as a tag.
    var systemName: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .dining: .categoryDining
        case .groceries: .categoryGroceries
        case .drinks: .categoryDrinks
        case .transport: .categoryTransport
        case .flights: .categoryFlights
        case .accommodation: .categoryAccommodation
        case .entertainment: .categoryEntertainment
        case .shopping: .categoryShopping
        case .bills: .categoryBills
        case .health: .categoryHealth
        case .gifts: .categoryGifts
        case .other: .categoryOther
        }
    }
}

// MARK: - Expense

extension Expense {
    /// The category somebody chose, if anybody did.
    ///
    /// `nil` covers three cases that behave identically and should: never set,
    /// set and then cleared, and set to something this build has never heard of
    /// because a newer version of the app invented it and synced it down here.
    /// The last is why this flat-maps rather than force-unwrapping — the same
    /// reasoning as `ExpenseGroup.appearance` and `Person.chosenColor`.
    ///
    /// No derived fallback, unlike a group's symbol. An icon guessed from an id
    /// is decoration and cannot be wrong; a *category* guessed from one would be
    /// the app asserting that a taxi was groceries.
    var category: ExpenseCategory? {
        get { symbolName.flatMap(ExpenseCategory.init(rawValue:)) }
        set { symbolName = newValue?.rawValue }
    }
}
