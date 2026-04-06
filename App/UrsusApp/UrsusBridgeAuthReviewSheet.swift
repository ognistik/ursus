import BearApplication
import SwiftUI

struct UrsusBridgeAuthReviewSheet: View {
    @ObservedObject var model: UrsusAppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        UrsusScrollSurface {
            VStack(alignment: .leading, spacing: 20) {
                header

                UrsusMessageStack(
                    success: model.bridgeAuthStatusMessage,
                    warning: nil,
                    error: model.bridgeAuthStatusError
                )

                if model.bridgeAuthPendingRequests.isEmpty && model.bridgeAuthGrantSummaries.isEmpty {
                    emptyState
                } else {
                    if !model.bridgeAuthPendingRequests.isEmpty {
                        pendingSection
                    }

                    if !model.bridgeAuthGrantSummaries.isEmpty {
                        grantsSection
                    }
                }
            }
        }
        .frame(width: 700, height: 620)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bridge Access Review")
                    .font(.system(size: 28, weight: .black))
                    .tracking(-1.4)

                Text("Approve or deny pending OAuth requests from remote bridge clients, and revoke remembered grants when you want a client to ask again.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let summary = model.bridgeAuthSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if model.bridgeAuthActionInProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .disabled(model.bridgeAuthActionInProgress)
            }
        }
    }

    private var pendingSection: some View {
        UrsusPanel(
            title: "Pending Requests",
            subtitle: "These requests are waiting for a local decision before the OAuth client can continue.",
            surface: .subtle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.bridgeAuthPendingRequests) { request in
                    UrsusGroupedBlock {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.clientTitle)
                                    .font(.callout.weight(.semibold))

                                if let resource = request.resource {
                                    Text(resource)
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }

                            Spacer(minLength: 12)

                            Text(request.status.rawValue.capitalized)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            authDetailRow(label: "Scope", value: request.requestedScope)
                            authDetailRow(label: "Redirect", value: request.redirectURI)
                            authDetailRow(label: "Expires", value: request.expiresAt.formatted(date: .abbreviated, time: .shortened))
                        }

                        HStack(spacing: 10) {
                            Button("Approve") {
                                model.approveBridgeAuthorizationRequest(request)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.bridgeAuthActionInProgress)

                            Button("Deny", role: .destructive) {
                                model.denyBridgeAuthorizationRequest(request)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.bridgeAuthActionInProgress)
                        }
                    }
                }
            }
        }
    }

    private var grantsSection: some View {
        UrsusPanel(
            title: "Remembered Grants",
            subtitle: "Approved clients can authorize again without prompting until you revoke their remembered access.",
            surface: .subtle
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.bridgeAuthGrantSummaries) { grant in
                    UrsusGroupedBlock {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(grant.clientTitle)
                                    .font(.callout.weight(.semibold))

                                if let resource = grant.resource {
                                    Text(resource)
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                        .textSelection(.enabled)
                                }
                            }

                            Spacer(minLength: 12)

                            Button("Revoke", role: .destructive) {
                                model.revokeBridgeGrant(grant)
                            }
                            .buttonStyle(.bordered)
                            .disabled(model.bridgeAuthActionInProgress)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            authDetailRow(label: "Scope", value: grant.scope)
                            authDetailRow(label: "Approved", value: grant.createdAt.formatted(date: .abbreviated, time: .shortened))
                            authDetailRow(label: "Updated", value: grant.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        UrsusPanel(
            title: "No Bridge Access To Review",
            subtitle: "New bridge OAuth requests will appear here when they need local approval.",
            surface: .subtle
        ) {
            Text("There are no pending requests or remembered grants right now.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func authDetailRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
