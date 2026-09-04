/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Where an expense happened: a name, and the point it stands on.
///
/// One value rather than three parameters, because these three attributes are
/// only ever meaningful together — a coordinate with no name is a dot nobody
/// can read, and `GroupStore` gaining a `latitude:` and a `longitude:` beside
/// its existing eleven arguments is how a call site starts passing them in the
/// wrong order.
///
/// Foundation only, deliberately: it holds two `Double`s rather than a
/// `CLLocationCoordinate2D` so that the store, the form's state and the model
/// layer need no CoreLocation import. MapKit stays in `NearbyPlaces`, which is
/// the one file that talks to it.
struct ExpensePlace: Equatable {
    let name: String

    /// The point, or `nil` when there isn't one.
    ///
    /// Optional as a *pair*, and never as two independent optionals: half a
    /// coordinate is not a location, and a type that can hold one would push
    /// that check onto everything that reads it.
    let latitude: Double?
    let longitude: Double?

    init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        // Both or neither, enforced here so no reader has to wonder.
        let paired = latitude != nil && longitude != nil
        self.latitude = paired ? latitude : nil
        self.longitude = paired ? longitude : nil
    }

    /// From a place the user picked out of the Nearby sheet.
    init(_ place: NearbyPlaces.Place) {
        self.init(
            name: place.name,
            latitude: place.latitude,
            longitude: place.longitude
        )
    }

    /// From what an expense already has stored, or `nil` if it has no place.
    ///
    /// The name is what decides. An expense can carry a name and no
    /// coordinates — everything attached by the build that shipped `Dutch 8`
    /// does — and that is still a place worth showing; a coordinate with no
    /// name is not, and cannot arise from any path in the app.
    init?(_ expense: Expense) {
        guard let name = expense.placeName?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty
        else { return nil }

        self.init(
            name: name,
            latitude: expense.latitude?.doubleValue,
            longitude: expense.longitude?.doubleValue
        )
    }

    /// Whether this can be opened on a map.
    ///
    /// False for every place attached before `Dutch 9`, and for anything a
    /// future path attaches by name alone — so the row that offers Maps has to
    /// ask rather than assume.
    var isMappable: Bool { latitude != nil && longitude != nil }
}
