/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import StoreKit
import SwiftUI

/// The one screen that asks for money.
///
/// Reached two ways: automatically, when creating a group would pass the free
/// limit, and deliberately, from the row at the bottom of the group list. The
/// second path exists so there is always a way to reach "Restore Purchases"
/// without first being blocked by something — App Review looks for exactly
/// that, and a customer whose entitlement didn't sync should not have to
/// provoke a paywall to fix it.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var purchases = PurchaseStore.shared

    /// True when the user arrived by hitting the limit rather than by choosing
    /// to look. Only changes the opening line — what is being sold, and for how
    /// much, is identical either way.
    let reachedLimit: Bool

    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 16) {
                        Benefit(
                            symbol: "rectangle.3.group",
                            title: "Unlimited groups",
                            detail: "Start a new trip, dinner or flatshare whenever you need one."
                        )
                        Benefit(
                            symbol: "qrcode.viewfinder",
                            title: "Joining stays free",
                            detail: "Anyone can scan your code and join, with or without this."
                        )
                        Benefit(
                            symbol: "checkmark.seal",
                            title: "Pay once, keep it",
                            detail: "Not a subscription. Works on all your devices, and for everyone in your Family Sharing group."
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    purchaseControls
                }
                .padding(20)
            }
            .navigationTitle("Dutch Unlimited")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .errorBanner($message)
            .task { await purchases.load() }
            // Dismisses itself the moment the entitlement lands, however it
            // landed — our own purchase, a restore, or an Ask to Buy approved
            // while this was on screen.
            .onChange(of: purchases.hasUnlimitedGroups) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "infinity")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(reachedLimit ? "You've used your free group" : "One group is free")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(
                reachedLimit
                    ? "Delete it to start another, or unlock as many as you like."
                    : "Unlock as many as you like with a single purchase."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var purchaseControls: some View {
        VStack(spacing: 12) {
            if purchases.loadFailed && purchases.product == nil {
                // No price means no honest button to show. Say why, and offer
                // the only thing that can help.
                Text(.appStoreUnreachable)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button("Try Again") {
                    Task { await purchases.load() }
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: buy) {
                    Group {
                        if purchases.isWorking {
                            ProgressView()
                        } else if let price = purchases.product?.displayPrice {
                            // The price is never written in the source. It
                            // arrives localized and converted for the user's
                            // storefront, and follows any change made in App
                            // Store Connect after this build shipped.
                            Text("Unlock for \(price)")
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchases.product == nil || purchases.isWorking)
                .accessibilityLabel(Text(buyAccessibilityLabel))

                Text(.oneTimePurchase)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Restore Purchases", action: restore)
                .font(.footnote)
                .disabled(purchases.isWorking)
                // 44pt minimum, which a footnote-sized button does not reach
                // on its own.
                .frame(minHeight: 44)
        }
    }

    /// Spelled out for VoiceOver, because "Unlock for $4.99" leaves the two
    /// facts that matter — what is unlocked, and that it happens once — to the
    /// surrounding text this button doesn't carry.
    private var buyAccessibilityLabel: String {
        guard let price = purchases.product?.displayPrice else {
            return String(localized: "Loading the price")
        }
        return String(
            localized: "Unlock unlimited groups for \(price), one-time purchase",
            comment: "VoiceOver label on the buy button. The placeholder is a storefront-formatted price."
        )
    }

    // MARK: - Actions

    private func buy() {
        Task {
            switch await purchases.purchase() {
            case .purchased:
                // `onChange` dismisses. Nothing to say — the sheet going away
                // and the group being created is the confirmation.
                break
            case .cancelled:
                break
            case .pending:
                message = "That purchase needs approval. It'll unlock once it goes through."
            case .failed(let reason):
                message = reason
            }
        }
    }

    private func restore() {
        Task {
            if await purchases.restore() == false {
                message = "No previous purchase was found on this Apple Account."
            }
        }
    }
}

// MARK: - Benefit

private struct Benefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            PaywallView(reachedLimit: true)
        }
}
