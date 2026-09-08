/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI

/// A transient, non-blocking error message pinned to the bottom of a screen.
///
/// This replaces the modal alerts the app used to raise for save failures. An
/// alert stops everything to say something the user can only acknowledge, and
/// on the expense form it does it while they are mid-entry. A banner reports
/// the same thing without taking the screen — which matters most exactly where
/// the user has unsaved input worth protecting.
private struct ErrorBannerModifier: ViewModifier {
    @Binding var message: String?

    /// The banner slides up from the bottom edge, which is the one piece of
    /// travel in the app that Reduce Motion should remove. It fades instead —
    /// a cross-fade rather than nothing at all, because unlike a balance
    /// changing under you this *is* an event, and it has to be noticed to be
    /// read before it clears itself six seconds later.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                // The animation is scoped to this stack rather than to
                // `content`, so it drives the banner in and out without also
                // animating unrelated changes in the screen behind it.
                ZStack {
                    if let message {
                        banner(message)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .move(edge: .bottom).combined(with: .opacity)
                            )
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: message)
            }
            // Both jobs hang off the same `id`, which changes exactly when a
            // message arrives — and runs after the banner has been rendered,
            // which is when VoiceOver is ready to be told about it.
            .task(id: message) {
                guard let text = message else { return }
                announce(text)
                // Long enough to read a sentence, short enough that a stale
                // failure isn't still on screen two actions later.
                try? await Task.sleep(for: .seconds(6))
                message = nil
            }
    }

    /// Speaks the failure, because nothing else here does.
    ///
    /// This banner replaced modal alerts, and an alert announces itself and
    /// takes VoiceOver focus. An `overlay` does neither: the banner appears,
    /// sits for six seconds and clears itself without a word, so a save that
    /// failed was indistinguishable from one that worked for anyone not
    /// looking at the screen. This is the app's only failure channel.
    ///
    /// An announcement rather than moving focus, deliberately. The banner is
    /// most often raised over a form somebody is part-way through typing into
    /// — `ExpenseFormView` is the case this whole modifier exists for — and
    /// yanking focus out of that to read one sentence would cost more than it
    /// carries.
    ///
    /// `.high` priority because the thing being announced disappears. A
    /// default-priority announcement is dropped if VoiceOver happens to be
    /// mid-utterance, and the sentence it was dropped in favour of is usually
    /// the very tap that just failed.
    private func announce(_ text: String) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .font(.title3)

            Text(text)
                .font(.subheadline)
                // Never truncate an error. At large type sizes the one useful
                // sentence is the first thing a line limit would cut.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Dismiss", systemImage: "xmark") {
                message = nil
            }
            .labelStyle(.iconOnly)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .contentShape(.rect)
            // Cancels out the frame's padding so the glyph still sits on the
            // same optical line as the text, while keeping the 44pt target.
            .padding(-12)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(uiColor: .separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

extension View {
    /// Presents `message` as a dismissible banner over the bottom of this view.
    func errorBanner(_ message: Binding<String?>) -> some View {
        modifier(ErrorBannerModifier(message: message))
    }
}

#Preview {
    // A wrapper rather than `@Previewable`, which needs a newer deployment
    // target than this app builds against.
    struct Harness: View {
        @State private var message: String? =
            "The group couldn't be saved because iCloud is unavailable."

        var body: some View {
            NavigationStack {
                List {
                    Button("Show error") {
                        message = "The group couldn't be saved because iCloud is unavailable."
                    }
                }
                .navigationTitle("Preview")
                .errorBanner($message)
            }
        }
    }

    return Harness()
}
