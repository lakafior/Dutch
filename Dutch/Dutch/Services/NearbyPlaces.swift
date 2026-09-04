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
        /// The street, where MapKit knows one. Shown under the name to tell two
        /// branches of the same chain apart, which is the only job it has.
        let street: String?
        /// Metres from the fix, for ordering and for the trailing label.
        let distance: CLLocationDistance
        /// ISO 3166 country of the place itself — the input to the currency
        /// prefill. Optional because MapKit does not promise it, and a missing
        /// one has to mean "don't prefill" rather than "prefill with home".
        let regionCode: String?
    }

    /// Why a search came back with nothing, in the two flavours the sheet has
    /// to word differently.
    enum Failure: Error {
        /// Permission was refused, or is restricted by policy. The only route
        /// back is Settings.app, so the sheet says so.
        case notPermitted
        /// The fix or the search didn't come back — no signal, roaming off,
        /// MapKit throttled. Deliberately one case: the user can do nothing
        /// about any of them, and three phrasings of "try again later" is three
        /// ways of saying the field below still works.
        case unavailable
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
    /// Throws `Failure.unavailable` rather than the underlying `MKError` or
    /// `CLError`: the trip abroad is exactly where roaming is off, and every
    /// one of those errors reaches the user as the same sentence.
    func nearby() async throws -> [Place] {
        guard isOffered else { throw Failure.notPermitted }

        let fix: CLLocation
        switch await currentLocation() {
        case .success(let location): fix = location
        case .failure(let failure): throw failure
        }

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
        } catch {
            throw Failure.unavailable
        }

        return response.mapItems
            .compactMap { Self.place($0, from: fix) }
            .sorted { $0.distance < $1.distance }
    }

    private static func place(_ item: MKMapItem, from fix: CLLocation) -> Place? {
        // A nameless point of interest is not a title anybody would pick.
        guard let name = item.name, !name.isEmpty else { return nil }

        let placemark = item.placemark
        let distance = placemark.location.map(fix.distance(from:)) ?? .greatestFiniteMagnitude

        return Place(
            name: name,
            street: placemark.thoroughfare,
            distance: distance,
            regionCode: placemark.isoCountryCode
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
        guard pendingFix == nil else { return .failure(.unavailable) }

        return await withCheckedContinuation { continuation in
            pendingFix = continuation
            manager.requestLocation()
        }
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
            guard let fix = locations.last else { return deliver(.failure(.unavailable)) }
            deliver(.success(fix))
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        MainActor.assumeIsolated { deliver(.failure(.unavailable)) }
    }
}
