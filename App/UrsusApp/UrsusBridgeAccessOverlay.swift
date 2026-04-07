import AppKit
import BearApplication
import SwiftUI

struct UrsusBridgeAccessOverlay: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.bridgeAuthStatusMessage != nil || model.bridgeAuthStatusError != nil {
                UrsusMessageStack(
                    success: model.bridgeAuthStatusMessage,
                    warning: nil,
                    error: model.bridgeAuthStatusError
                )
            }

            if model.bridgeAuthGrantSummaries.isEmpty {
                emptyState
            } else {
                grantList
            }
        }
        .padding(24)
        .frame(maxWidth: 760, maxHeight: 520, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 24, y: 10)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bridge Access")
                    .font(.system(size: 28, weight: .black))
                    .tracking(-1.2)

                Text("Review and revoke remembered client access for the Remote MCP Bridge.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                if model.bridgeAuthActionInProgress {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Close") {
                    model.closeBridgeAccessOverlay()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(model.bridgeAuthActionInProgress)
            }
        }
    }

    private var grantList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.bridgeAuthGrantSummaries.enumerated()), id: \.element.id) { index, grant in
                    grantRow(grant)

                    if index < model.bridgeAuthGrantSummaries.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No remembered clients yet.")
                .font(.headline)

            Text("Approved bridge clients will appear here after OAuth consent is granted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func grantRow(_ grant: BearBridgeAuthGrantSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(grant.clientTitle)
                    .font(.callout.weight(.semibold))

                if let resource = grant.resource, !resource.isEmpty {
                    Text(resource)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Approved \(grant.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Revoke", role: .destructive) {
                model.revokeBridgeGrant(grant)
            }
            .buttonStyle(.bordered)
            .disabled(model.bridgeAuthActionInProgress)
        }
        .padding(.vertical, 14)
    }
}
