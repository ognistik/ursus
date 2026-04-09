import BearApplication
import SwiftUI

struct UrsusBridgeAccessOverlay: View {
    @ObservedObject var model: UrsusAppModel
    @State private var showsRevokeAllConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.bridgeAuthStatusError != nil {
                UrsusMessageStack(error: model.bridgeAuthStatusError)
            }

            if model.bridgeAuthGrantSummaries.isEmpty {
                emptyState
            } else {
                grantList
            }
        }
        .padding(22)
        .frame(maxWidth: 560, minHeight: 260, maxHeight: 430, alignment: .topLeading)
        .ursusRoundedSurface(
            background: ursusSheetBackgroundColor,
            border: ursusSurfaceBorderStrongColor,
            cornerRadius: 22
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, y: 10)
        .confirmationDialog(
            "Revoke all access?",
            isPresented: $showsRevokeAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke All", role: .destructive) {
                model.revokeAllBridgeAccess()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All remembered bridge clients will need to authorize again.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bridge Access")
                    //.font(.system(size: 24, weight: .black))
                    .font(.custom("Montserrat-Regular", size: 20))
                    .tracking(0)

                Text("Review and revoke remembered client access for the Remote MCP Bridge.")
                    .font(.footnote)
                    .foregroundStyle(ursusTertiaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 10) {
                HStack(spacing: 10) {
                    if model.bridgeAuthActionInProgress {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        model.closeBridgeAccessOverlay()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ursusInlineLabelColor)
                            .frame(width: 28, height: 28)
                            .background(ursusSecondaryControlFillColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.bridgeAuthActionInProgress)
                    .help("Dismiss")
                }

                if !model.bridgeAuthGrantSummaries.isEmpty {
                    Button("Revoke All", role: .destructive) {
                        showsRevokeAllConfirmation = true
                    }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .disabled(model.bridgeAuthActionInProgress)
                }
            }
        }
    }

    private var grantList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.bridgeAuthGrantSummaries.enumerated()), id: \.element.id) { index, grant in
                        grantRow(grant)

                        if index < model.bridgeAuthGrantSummaries.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .ursusCustomScrollChrome()
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .top)
        .ursusRoundedSurface(
            background: ursusGroupedBlockBackgroundColor,
            border: ursusSurfaceBorderColor,
            cornerRadius: 14
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No remembered clients yet.")
                .font(.headline)

            Text("Approved bridge clients will appear here after OAuth consent is granted.")
                .font(.callout)
                .foregroundStyle(ursusSecondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .ursusRoundedSurface(
            background: ursusGroupedBlockBackgroundColor,
            border: ursusSurfaceBorderColor,
            cornerRadius: 14
        )
    }

    private func grantRow(_ grant: BearBridgeAuthGrantSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(grant.clientTitle)
                    .font(.callout.weight(.semibold))

                if let resource = grant.resource, !resource.isEmpty {
                    Text(resource)
                        .font(.footnote)
                        .foregroundStyle(ursusTertiaryTextColor)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Approved \(grant.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.footnote)
                    .foregroundStyle(ursusSecondaryTextColor)
            }

            Spacer(minLength: 12)

            Button("Revoke", role: .destructive) {
                model.revokeBridgeGrant(grant)
            }
            .ursusButtonStyle(.destructive)
            .disabled(model.bridgeAuthActionInProgress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
