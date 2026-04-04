import BearApplication
import BearCore
import SwiftUI

struct UrsusToolsView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 24) {
                    if launcherPrimaryActionTitle(for: settings) != nil {
                        launcherPanel(settings)
                        Divider()
                    }
                    toolAvailabilityPanel(settings)
                }
            } else {
                unavailablePanel(
                    title: "Tools are unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private func launcherPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Launcher") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    UrsusStatusBadge(title: compactStatusTitle(for: settings.launcherStatus), status: settings.launcherStatus)
                    Text(settings.launcherStatusDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let actionTitle = launcherPrimaryActionTitle(for: settings) {
                    Button(actionTitle) {
                        model.installPublicLauncher()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.currentBundledCLIPath == nil)
                }

                UrsusMessageStack(
                    success: model.cliStatusMessage,
                    warning: nil,
                    error: model.cliStatusError
                )
            }
        }
    }

    private func toolAvailabilityPanel(_ settings: BearAppSettingsSnapshot) -> some View {
        let sections: [(category: BearToolCategory, tools: [BearAppToolToggleSnapshot])] = BearToolCategory.allCases.compactMap { category in
            let tools = settings.toolToggles.filter { $0.category == category }
            return tools.isEmpty ? nil : (category, tools)
        }

        return VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, entry in
                let category = entry.category
                let tools = entry.tools

                if index > 0 {
                    Divider()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(category.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                            Toggle(isOn: Binding(
                                get: { model.isToolEnabledInDraft(tool.tool) },
                                set: { model.setToolEnabledInDraft(tool.tool, enabled: $0) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(tool.title)
                                        .font(.subheadline)
                                    Text(tool.summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(14)

                            if index < tools.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
            }

            UrsusMessageStack(
                success: model.configurationValidation.warnings.isEmpty ? model.configurationStatusMessage : nil,
                warning: model.configurationValidation.warnings.isEmpty ? nil : model.configurationStatusMessage,
                error: model.configurationStatusError
            )
        }
    }
}
