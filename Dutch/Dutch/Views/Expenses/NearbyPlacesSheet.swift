/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import MapKit
import UIKit

/// The list of places to name an expense after.
///
/// Deliberately a sheet the user opened rather than anything that happens to
/// the form on its own: the title on an expense is optional by design, and a
/// screen that fills it in without being asked reintroduces the field people
/// have to stop and check.
///
/// Every way this can fail ends in the same place — the sheet closes, or says
/// one sentence and closes — because the text field behind it has always
/// worked. An error the user can do nothing about, in front of a form they were
/// halfway through, is worse than no button at all.
struct NearbyPlacesSheet: View {
    /// What the form does with the choice: the name goes in the title, and the
    /// country goes to the currency prefill if that is switched on.
    let onPick: (NearbyPlaces.Place) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var places: [NearbyPlaces.Place] = []
    @State private var failure: NearbyPlaces.Failure?
    @State private var isSearching = true

    /// Localized by the system, and it reads distances the way the phone's
    /// region does — metres here, feet in Texas. Static because a formatter per
    /// row is a formatter built ten times for one glance.
    private static let distances: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Nearby")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .task { await search() }
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text(.nearbySearching))
        } else if let failure {
            unavailable(failure)
        } else if places.isEmpty {
            ContentUnavailableView(
                "Nothing Nearby",
                systemImage: "mappin.slash",
                description: Text(.nearbyNothingFoundExplanation)
            )
        } else {
            List {
                Section {
                    ForEach(places, content: row)
                } footer: {
                    // Only on the fallback. A screen asked "what is around me"
                    // that answers with a street number has to say why, or it
                    // reads as the search having gone wrong.
                    if places.contains(where: \.isAddress) {
                        Text(.nearbyAddressExplanation)
                    }
                }
            }
        }
    }

    private func row(_ place: NearbyPlaces.Place) -> some View {
        Button {
            onPick(place)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .foregroundStyle(.primary)

                    if let street = place.street {
                        Text(street)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 12)

                if let distance = place.distance {
                    Text(Self.distances.string(fromDistance: distance))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        // Read as part of the row's label below, which puts the
                        // name first — VoiceOver arriving at "80 m" before the
                        // café it belongs to is a list you have to hear twice.
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label(for: place)))
    }

    /// Name first, distance after, and no distance at all on the address —
    /// which is not a distance away from anything.
    private func label(for place: NearbyPlaces.Place) -> String {
        guard let distance = place.distance else { return place.name }
        return "\(place.name), \(Self.distances.string(fromDistance: distance))"
    }

    /// Each dead end named for the thing that actually gave up.
    ///
    /// One of them the user can fix in Settings; the other two they cannot fix
    /// at all, and are still worth telling apart — the first version said
    /// "couldn't reach Apple Maps" for a phone that had simply never got a
    /// location fix, which sends anybody debugging it after the wrong half.
    @ViewBuilder
    private func unavailable(_ failure: NearbyPlaces.Failure) -> some View {
        switch failure {
        case .notPermitted:
            ContentUnavailableView {
                Label("Location Is Off", systemImage: "location.slash")
            } description: {
                Text(.nearbyPermissionExplanation)
            } actions: {
                Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                    Text("Open Settings")
                }
            }
        case .noFix:
            ContentUnavailableView(
                "Can't Find You",
                systemImage: "location.slash",
                description: Text(.nearbyNoFixExplanation)
            )
        case .searchFailed:
            ContentUnavailableView(
                "Can't Look Around",
                systemImage: "wifi.slash",
                description: Text(.nearbyUnavailableExplanation)
            )
        }
    }

    private func search() async {
        isSearching = true
        defer { isSearching = false }

        do {
            places = try await NearbyPlaces.shared.nearby()
        } catch let error as NearbyPlaces.Failure {
            failure = error
        } catch {
            failure = .searchFailed
        }
    }
}
