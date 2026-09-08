/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// One day of the log, as the expense list renders it.
///
/// Grouped in memory rather than through a `SectionedFetchRequest`, which wants
/// its section identifier to be a property Core Data can sort on — that would
/// have meant a stored day string on every `Expense`, a model version to add it,
/// a CloudKit schema promotion, and a value that has to be kept in step with the
/// date beside it forever. The fetch already hands these over sorted by date, so
/// the grouping is one pass with a comparison in it.
struct ExpenseDay: Identifiable {
    let day: Date
    var expenses: [Expense]

    var id: Date { day }

    /// "Today", "Yesterday", or the date. Relative wording only where it is
    /// genuinely easier to place than a date — past yesterday, "3 weeks ago" is
    /// something to work out rather than read, and the weekday is what somebody
    /// reconstructing a trip actually remembers.
    ///
    /// `String(localized:)` rather than bare literals: this returns a `String`,
    /// and `Text(aString)` takes the *non*-localizing initializer — so the three
    /// relative words stayed English in every language while the dates beside
    /// them translated themselves through `formatted`. Caught in the Polish App
    /// Store screenshots, where the expense log read "Today" under a Polish
    /// heading.
    var title: String {
        let calendar = Calendar.current
        if day == .distantPast { return String(localized: "Undated") }
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
    }
}
