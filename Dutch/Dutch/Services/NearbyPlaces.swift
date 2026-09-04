/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreLocation
import MapKit
import SwiftUI

/// The places you could be sitting in right now, offered as titles for an
/// expense.
///
/// One tap — **Nearby** on the expense form — reads the location once, asks
/// MapKit what is within a short walk, and hands back a list of names. Nothing
/// here runs on its own: there is no monitoring, no significant-change
/// subscription, and no background mode, so the app knows where the phone is
/// only during the second or two after somebody asked it to find out.
///
/// That is the whole design, and it is what makes the rest of the batch
/// acceptable. The currency prefill reads the *country of the place that was
/// picked* rather than taking a second fix of its own, and the place stored on
/// an expense is a name the user chose out loud. Neither is a thing the app
/// decided to look up on its own initiative.
///
/// Shaped after `ExpenseNotifier`, which is this codebase's worked example of a
/// permission-gated feature: a persisted preference that is never the same
/// question as the system's authorization, an `enable()` that can come back
/// refused, and a settings screen able to say which of the two is off.
@MainActor
final class NearbyPlaces: NSObject, ObservableObject {
    static let shared = NearbyPlaces()

    /// One candidate title.
    ///
    /// A value type rather than the `MKMapItem` it came from: the map item is a
    /// reference type carrying a whole placemark, and the two things the app
    /// actually wants from it — a name and a country — are better copied out at
    /// the boundary than carried through the form.
    struct Place: Identifiable, Hashable {
        let id = UUID()
        let name: String
        /// The street or the town, depending on which of the two the name above
        /// already is. Its only job is telling two branches of the same chain
        /// apart.
        let street: String?
        /// Metres from the fix, for ordering and for the trailing label.
        ///
        /// `nil` for the address fallback, which is not *near* anywhere — it is
        /// where you are standing, and "0 m" trailing it reads like a bug.
        let distance: CLLocationDistance?
        /// ISO 3166 country of the place itself — the input to the currency
        /// prefill. Optional because MapKit does not promise it, and a missing
        /// one has to mean "don't prefill" rather than "prefill with home".
        let regionCode: String?
        /// The point itself, kept so the expense it is attached to can be
        /// opened on a map later. Optional because a placemark is not obliged
        /// to have one, and a row with no coordinate is still a usable title.
        let latitude: Double?
        let longitude: Double?

        /// Whether this came from the address fallback rather than from the
        /// list of places.
        ///
        /// The sheet reads it to explain itself: a screen that answers "what is
        /// around me" with a street number, and doesn't say why, looks like the
        /// search returned something absurd.
        let isAddress: Bool

        init(
            name: String,
            street: String?,
            distance: CLLocationDistance?,
            regionCode: String?,
            coordinate: CLLocationCoordinate2D?,
            isAddress: Bool = false
        ) {
            self.name = name
            self.street = street
            self.distance = distance
            self.regionCode = regionCode
            // Unwrapped here, at the one boundary that has CoreLocation, so
            // nothing downstream needs it — see `ExpensePlace`.
            self.latitude = coordinate?.latitude
            self.longitude = coordinate?.longitude
            self.isAddress = isAddress
        }
    }

    /// Why a search came back with nothing.
    ///
    /// Three cases and not one, which is a correction: the first version
    /// collapsed every failure into a single "couldn't reach Apple Maps", on
    /// the reasoning that the user can do nothing about any of them. True for
    /// the user, and useless for anybody trying to find out *why* — a phone
    /// that never got a location fix and a phone with no signal produced the
    /// same sentence, and the sentence blamed the wrong half.
    ///
    /// They are still all dead ends with the same remedy, so none of them is an
    /// alert and none offers a retry. They differ only in naming what didn't
    /// answer.
    enum Failure: Error {
        /// Permission was refused, or is restricted by policy. The only route
        /// back is Settings.app, so the sheet says so.
        case notPermitted
        /// CoreLocation never produced a fix — indoors, airplane mode, or a
        /// simulator with no simulated location set.
        case noFix
        /// The fix arrived but MapKit didn't answer: no signal, roaming off, or
        /// throttled.
        case searchFailed
    }

    /// Whether the user has asked for this at all. Persisted, and never the
    /// same question as `authorization` — iOS can revoke permission in Settings
    /// while the app is backgrounded, and the settings screen has to be able to
    /// tell the two apart.
    @Published private(set) var isEnabled: Bool

    /// What CoreLocation currently thinks. Refreshed when the settings screen
    /// appears, for the same reason the notification status is.
    @Published private(set) var authorization: CLAuthorizationStatus

    /// Whether this can be offered at all.
    ///
    /// False under `-uitesting-reset`, matching `SpotlightIndexer`: a UI test
    /// must never be able to raise a system alert, and a permission prompt is
    /// the one kind of dialog the test harness cannot dismiss.
    let isAvailable: Bool

    /// A little wider than the hundred metres this feature is described in.
    ///
    /// A city fix is good to some tens of metres and the phone is indoors when
    /// it matters, so a radius that matched the promise exactly would put the
    /// café you are sitting in just outside it — which reads as the feature not
    /// working rather than as a boundary being honoured.
    private static let radius: CLLocationDistance = 150

    /// Food and drink, and nothing else.
    ///
    /// Widening this is one line, and it is the wrong instinct: the request was
    /// for the café at the table, and a filter that also admits shops, museums
    /// and petrol stations turns one tap into a list to read. A group that
    /// spends on those still has the text field it has always had.
    private static let categories: [MKPointOfInterestCategory] = [
        .restaurant, .cafe, .bakery, .brewery, .winery, .nightlife, .foodMarket
    ]

    private static let enabledKey = "nearby.places"

    private let defaults: UserDefaults
    private let manager = CLLocationManager()

    /// The one-shot waits. Each is cleared *before* it is resumed: a
    /// continuation resumed twice is a crash rather than a bug you can see, and
    /// CoreLocation is entitled to call back more than once.
    private var pendingAuthorization: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var pendingFix: CheckedContinuation<Result<CLLocation, Failure>, Never>?

    init(defaults: UserDefaults = PersistenceController.appGroupDefaults) {
        self.defaults = defaults
        self.isAvailable = !ProcessInfo.processInfo.arguments.contains("-uitesting-reset")
        self.isEnabled = defaults.bool(forKey: Self.enabledKey)
        self.authorization = manager.authorizationStatus
        super.init()

        manager.delegate = self
        // Enough to know which street you are on, which is all a 150 m search
        // needs. Best-accuracy would spend the GPS budget resolving a precision
        // this feature throws away.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Preference

    /// Turns the feature on, asking iOS for permission the first time.
    ///
    /// The prompt lives here, on a switch somebody reached for, rather than in
    /// front of the expense form — which is the entire reason this shipped as a
    /// button and a setting instead of a prefill. Asked cold at the table, the
    /// question arrives before the person has any idea what it is for, and a
    /// denial is close to permanent.
    ///
    /// Returns whether the switch should end up on.
    @discardableResult
    func enable() async -> Bool {
        guard isAvailable else { return false }

        let status = await requestAuthorization()
        let granted = Self.isGranted(status)
        setEnabled(granted)
        return granted
    }

    func disable() {
        setEnabled(false)
    }

    /// Re-reads what CoreLocation thinks, since permission can be withdrawn in
    /// Settings.app without the app running.
    func refreshAuthorization() {
        authorization = manager.authorizationStatus

        // A revoked permission turns the app's own preference off too, so the
        // settings screen shows one consistent answer rather than an "on"
        // switch above a button that cannot work.
        if isEnabled, !Self.isGranted(authorization) {
            setEnabled(false)
        }
    }

    /// Whether the **Nearby** button should appear on the expense form at all.
    ///
    /// Both halves matter: the preference is the user's answer, and the
    /// authorization is the system's. A button shown on the strength of the
    /// first alone is one that opens a sheet to explain it cannot work.
    var isOffered: Bool {
        isAvailable && isEnabled && Self.isGranted(authorization)
    }

    private static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    // MARK: - Searching

    /// The eating and drinking places within a short walk, nearest first.
    ///
    /// Throws a `Failure` rather than the underlying `MKError` or `CLError`:
    /// the trip abroad is exactly where roaming is off, and no error code
    /// belongs on a form somebody is halfway through. Which of the two stages
    /// gave up is preserved, because it is the difference between "your phone
    /// doesn't know where it is" and "Maps didn't answer" — and the real error
    /// goes to the console in a debug build.
    func nearby() async throws -> [Place] {
        guard isOffered else { throw Failure.notPermitted }

        let fix: CLLocation
        switch await currentLocation() {
        case .success(let location): fix = location
        case .failure(let failure): throw failure
        }

        return try await Self.search(around: fix)
    }

    private static func search(around fix: CLLocation) async throws -> [Place] {

        let request = MKLocalPointsOfInterestRequest(
            center: fix.coordinate,
            radius: Self.radius
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(
            including: Self.categories
        )

        // `MKLocalPointsOfInterestRequest`, and deliberately not
        // `MKLocalSearch.Request`: that one searches for *text* and would need
        // a query invented for it — "restaurant" — which returns the places
        // with that word in the name rather than the places that are one.
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            // **Not a failure.** MapKit reports "there is nothing here" by
            // throwing, so an earlier version of this method turned every quiet
            // street into "couldn't reach Apple Maps".
            return await address(at: fix)
        } catch {
            log("search failed", error)
            throw Failure.searchFailed
        }

        let places = response.mapItems
            .compactMap { place($0, from: fix) }
            .sorted { ($0.distance ?? .greatestFiniteMagnitude) < ($1.distance ?? .greatestFiniteMagnitude) }

        return places.isEmpty ? await address(at: fix) : places
    }

    /// The street you are standing on, when there was no place to offer.
    ///
    /// Deliberately a *fallback* and never the first answer. Reverse-geocoding
    /// was rejected outright when this feature was designed, and the rejection
    /// still holds for the version that was rejected: an expense titled
    /// *Kraków*, in a group already called *Kraków Trip*, tells nobody
    /// anything. A street is a different proposition — it is the one thing that
    /// distinguishes the market stall, the taxi and the beach bar that Maps has
    /// never heard of, and those are exactly the expenses that reach this path.
    ///
    /// It also restores the currency prefill on this path: the placemark
    /// carries `isoCountryCode` the same way a map item does, so somebody in a
    /// village with no listed café still gets the local currency offered.
    ///
    /// Returns `[]` rather than throwing when the geocoder refuses. Arriving
    /// here already means the search found nothing, and "nothing nearby" is a
    /// truthful answer to that — turning it into an error because the *second*
    /// lookup also failed would report a problem the user does not have.
    private static func address(at fix: CLLocation) async -> [Place] {
        let placemark: CLPlacemark?
        do {
            // Rate-limited by Apple, which this cannot hit: one call, only on
            // an empty search, only behind a tap.
            placemark = try await CLGeocoder().reverseGeocodeLocation(fix).first
        } catch {
            log("reverse geocode failed", error)
            return []
        }

        guard let mark = placemark, let name = addressLine(of: mark) else { return [] }

        return [
            Place(
                name: name,
                // The town under the street, which is the pair that reads as an
                // address. Dropped when the line above is already the town —
                // repeating it would render "Kraków / Kraków".
                street: mark.locality == name ? nil : mark.locality,
                distance: nil,
                regionCode: mark.isoCountryCode,
                // The placemark's own point where it has one, and otherwise the
                // fix it was derived from — which is the same spot to within
                // the accuracy this feature ever had.
                coordinate: (mark.location ?? fix).coordinate,
                isAddress: true
            )
        ]
    }

    /// The most specific line the placemark can offer, and never a bare town if
    /// there is anything better.
    ///
    /// `name` first because Foundation composes it per locale — a house number
    /// leads in Kraków and trails in London, and hand-assembling
    /// `thoroughfare` + `subThoroughfare` gets that backwards in half of
    /// Europe.
    private static func addressLine(of mark: CLPlacemark) -> String? {
        for candidate in [mark.name, mark.thoroughfare, mark.locality] {
            if let text = candidate?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// Opens a stored place in Apple Maps, dropping a pin that carries its
    /// name.
    ///
    /// Here rather than in the view, because this is the file that owns the
    /// MapKit import — `ExpensePlace` stays two `Double`s and a `String` so the
    /// store and the form need no framework for it.
    ///
    /// An `MKPlacemark` built from a coordinate rather than a search for the
    /// name: the name is what the user called it, not necessarily what Maps
    /// calls it, and searching would open whatever branch of the chain is
    /// nearest *now* — which on a trip home from Kraków is the wrong city.
    @discardableResult
    static func openInMaps(_ place: ExpensePlace) -> Bool {
        guard let latitude = place.latitude, let longitude = place.longitude else {
            return false
        }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = place.name
        return item.openInMaps()
    }

    /// Names the underlying error in a debug build and nowhere else.
    ///
    /// The three `Failure` cases are what the user is told, and they are
    /// deliberately vague — a `CLError` code on screen helps nobody at a dinner
    /// table. This is the other half of that trade: the real reason has to be
    /// readable *somewhere*, or the next report of "it says it can't look
    /// around" is unanswerable again.
    private static func log(_ what: String, _ error: Error) {
        #if DEBUG
        print("[Dutch] Nearby \(what): \(error)")
        #endif
    }

    private static func place(_ item: MKMapItem, from fix: CLLocation) -> Place? {
        // A nameless point of interest is not a title anybody would pick.
        guard let name = item.name, !name.isEmpty else { return nil }

        let placemark = item.placemark
        let distance = placemark.location.map(fix.distance(from:))

        return Place(
            name: name,
            street: placemark.thoroughfare,
            distance: distance,
            regionCode: placemark.isoCountryCode,
            coordinate: placemark.coordinate
        )
    }

    // MARK: - The fix

    private func requestAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else {
            authorization = status
            return status
        }

        let answer = await withCheckedContinuation { continuation in
            pendingAuthorization = continuation
            manager.requestWhenInUseAuthorization()
        }
        authorization = answer
        return answer
    }

    /// One fix, not a stream.
    ///
    /// `requestLocation()` delivers a single reading and stops the hardware by
    /// itself, which is the shape this feature wants: the phone's whereabouts
    /// are read once, in response to a tap, and then forgotten.
    private func currentLocation() async -> Result<CLLocation, Failure> {
        // A second tap while the first is still waiting would overwrite the
        // continuation and strand it, so the second one is refused instead.
        guard pendingFix == nil else { return .failure(.noFix) }

        return await withCheckedContinuation { continuation in
            pendingFix = continuation
            manager.requestLocation()
        }
    }

    /// Turns CoreLocation's own error into the right dead end.
    ///
    /// `CLError.denied` is the one that must not be reported as a missing fix:
    /// it means permission went away between the check at the top of `nearby()`
    /// and this callback — revoked in Settings.app while the sheet was
    /// opening — and the user needs the row that offers them Settings, not a
    /// sentence about signal.
    private static func failure(for error: Error) -> Failure {
        log("no fix", error)
        return (error as? CLError)?.code == .denied ? .notPermitted : .noFix
    }

    private func deliver(_ result: Result<CLLocation, Failure>) {
        guard let continuation = pendingFix else { return }
        pendingFix = nil
        continuation.resume(returning: result)
    }
}

// MARK: - CoreLocation

extension NearbyPlaces: CLLocationManagerDelegate {
    /// `MainActor.assumeIsolated` rather than a `Task`, matching
    /// `CloudSyncMonitor`: CoreLocation delivers on the run loop of the thread
    /// that created the manager, and this one is created in an initializer that
    /// only the main actor can call.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let status = manager.authorizationStatus
            authorization = status

            // Only the prompt's own answer resumes the wait. The same callback
            // fires for a change made in Settings.app, which nothing is
            // awaiting.
            if status != .notDetermined, let continuation = pendingAuthorization {
                pendingAuthorization = nil
                continuation.resume(returning: status)
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        MainActor.assumeIsolated {
            guard let fix = locations.last else { return deliver(.failure(.noFix)) }
            deliver(.success(fix))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated { deliver(.failure(Self.failure(for: error))) }
    }
}
