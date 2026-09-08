/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// A single glyph in the navigation bar saying where iCloud sync stands, and a
/// popover behind it saying it in words.
///
/// This replaced a permanent line of text under the group list. The line was
/// reporting an ambient state that is fine essentially always, which meant it
/// spent its whole life saying nothing had gone wrong — and the state it exists
/// for got no more emphasis than that.
///
/// It exists for its failure state. Everything about this app assumes sync
/// works, and when it doesn't — signed out, out of storage, on a plane — the
/// behaviour without this is for expenses to simply stop appearing on other
/// people's phones with nothing anywhere to explain it. Being told is the
/// difference between a bug report and a Settings trip.
///
/// Three decisions worth keeping:
///
/// - **The healthy state is grey, not green.** Green rewards the user for
///   something they didn't do and makes the quiet state loud. Colour is spent
///   only on the state that needs somebody to act.
/// - **Age is not a warning level.** `lastSync` only advances on a successful
///   *import* (see `CloudSyncMonitor.record`), so a healthy phone that nobody
///   has sent an expense to today can legitimately go a long time between
///   imports. Colouring that amber would light the indicator up most of the
///   time on a working device, and teach people to ignore the one state that
///   matters.
/// - **The states differ in shape, not only in tint.** Colour alone is not a
///   channel some people have.
///
/// The sentence lives in the popover rather than on screen because "your iCloud
/// storage is full" is only wanted at the moment somebody wonders — which is
/// exactly when they tap. That is also the only place left to mention
/// pull-to-refresh, which is not a discoverable gesture on its own.
struct SyncStatusIndicator: View {
    /// A plain `let`: `CloudSyncMonitor` is `@Observable`, so reading its
    /// properties in `body` below is what registers this view for updates.
    private let sync = CloudSyncMonitor.shared

    @State private var showingDetail = false

    /// Cached, because a toolbar item redraws with the list behind it.
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        if sync.isEnabled {
            Button {
                showingDetail = true
            } label: {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    // Replace rather than cut: the glyph changing is the only
                    // notice a state change gets now that no text is on screen.
                    .motionContentTransition(.symbolEffect(.replace))
                    // No `.symbolEffect(.pulse, isActive:)` here on purpose.
                    // `isSyncing` flips true within the first second of launch
                    // as mirroring starts up, which started a continuous, every-
                    // frame animated symbol effect on this toolbar glyph at the
                    // exact moment iOS 26.0.1's RenderBox is least warmed up.
                    // Field crash logs (iPhone 16, 26.0.1, ~0.9s after launch)
                    // show a SIGSEGV inside RB::Symbol::Glyph::Layer on the
                    // SwiftUI async symbol-render thread — an Apple-side bug,
                    // but this pulse was the only continuous animated symbol
                    // effect in the app and the only one guaranteed to run
                    // unconditionally at launch. Removing it stopped the crash.
                    // Don't reintroduce a looping symbolEffect on this glyph
                    // without confirming RenderBox is fixed.
                    .foregroundStyle(tint)
            }
            .accessibilityLabel("iCloud sync")
            .accessibilityValue(caption)
            .accessibilityHint("Shows sync details")
            .popover(isPresented: $showingDetail) {
                detail
                    // Without this a popover becomes a sheet on iPhone, which
                    // is far too much ceremony for one sentence.
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(sync.problem == nil ? Color.primary : Color.orange)

            Text(.pullToRefresh)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
        .padding(16)
        // Wide enough for the longest failure sentence in
        // `CloudSyncMonitor.describe` without it becoming a paragraph.
        .frame(maxWidth: 280, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var symbol: String {
        if sync.isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if sync.problem != nil { return "exclamationmark.icloud" }
        return sync.lastSync == nil ? "icloud" : "checkmark.icloud"
    }

    private var tint: Color {
        sync.problem == nil ? .secondary : .orange
    }

    private var caption: String {
        if sync.isSyncing { return String(localized: "Syncing with iCloud…") }
        if let problem = sync.problem { return problem }

        guard let lastSync = sync.lastSync else {
            // Not an error: mirroring may simply not have run its first import
            // yet, which is the normal state for the first seconds of a launch.
            return String(localized: "Waiting for iCloud")
        }

        // `RelativeDateTimeFormatter` renders the first minute as "in 0
        // seconds", which reads as a scheduled event rather than a finished
        // one — and the first minute is exactly when somebody who just pulled
        // the list is reading this.
        guard Date.now.timeIntervalSince(lastSync) >= 60 else {
            return String(localized: "Synced just now")
        }
        let ago = Self.relative.localizedString(for: lastSync, relativeTo: .now)
        return String(
            localized: "Synced \(ago)",
            comment: "The placeholder is an already-localized relative time, e.g. '2 hours ago'."
        )
    }
}
