import BearApplication
import BearCore
import SwiftUI

struct UrsusPreferencesView: View {
    @ObservedObject var model: UrsusAppModel
    @ObservedObject var updaterController: UrsusUpdaterController
    let showsStandaloneHeader: Bool

    var body: some View {
        UrsusScrollSurface {
            if let settings = model.dashboard.settings {
                VStack(alignment: .leading, spacing: 20) {
                    if showsStandaloneHeader {
                        UrsusScreenHeader(title: "Preferences")
                    }

                    UrsusRuntimeRestartGuidance()
                    Divider()
                    behaviorPanel
                    Divider()
                    inboxTagsPanel
                    Divider()
                    templatePanel(settings)
                    Divider()
                    limitsPanel
                    Divider()
                    appUpdatesPanel

                    UrsusMessageStack(error: model.configurationStatusError)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                unavailablePanel(
                    title: "Preferences are unavailable",
                    detail: model.dashboard.settingsError ?? "Ursus could not load its current settings."
                )
            }
        }
    }

    private var behaviorPanel: some View {
        UrsusPanel(
            title: "Note Behavior",
            titleHelpText: "Tools will use these defaults, but you can command the AI to override them in your requests."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Create opens note by default", isOn: autosavingBinding(\.createOpensNoteByDefaultDraft))
                Divider()
                Toggle("Open uses new window by default", isOn: autosavingBinding(\.openUsesNewWindowByDefaultDraft))
                Divider()
                Toggle("Create adds inbox tags by default", isOn: autosavingBinding(\.createAddsInboxTagsByDefaultDraft))
                Divider()
                segmentedPreferenceField(
                    label: "Default insert position",
                    selection: autosavingBinding(\.defaultInsertPositionDraft),
                    options: [
                        UrsusSegmentedOption(title: "Top", value: .top),
                        UrsusSegmentedOption(title: "Bottom", value: .bottom)
                    ]
                )
                Divider()
                segmentedPreferenceField(
                    label: "Tags merge mode",
                    selection: autosavingBinding(\.tagsMergeModeDraft),
                    options: [
                        UrsusSegmentedOption(title: "Append", value: .append),
                        UrsusSegmentedOption(title: "Replace", value: .replace)
                    ]
                )
            }
        }
    }

    private var inboxTagsPanel: some View {
        UrsusPanel(
            title: "Inbox Tags",
            titleHelpText: "Tags you keep ready for quick capture. When enabled in Note Behavior, new notes can start in this inbox automatically."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                UrsusTagEditor(
                    tags: model.inboxTagValues,
                    onAdd: model.addInboxTags(from:),
                    onRemove: model.removeInboxTag(_:)
                )

                configurationValidationMessages(for: .inboxTags)
            }
        }
    }

    private func templatePanel(_ settings: BearAppSettingsSnapshot) -> some View {
        UrsusPanel(title: "Template") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Enable template management", isOn: autosavingBinding(\.templateManagementEnabledDraft))

                if model.templateManagementEnabledDraft {
                    Text("Required slots: `{{content}}` and `{{tags}}`.")
                        .font(.caption)
                        .foregroundStyle(ursusTertiaryTextColor)

                    TextEditor(text: Binding(
                        get: { model.templateDraft },
                        set: { newValue in
                            model.templateDraft = limitedTemplateText(newValue, maxLines: 7)
                            model.templateDraftDidChange()
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .scrollDisabled(true)                   // no scrolling, no scrollbar
                    .scrollContentBackground(.hidden)
                    .frame(height: 7 * 16)                  // 20pt per line — adjust if needed
                    .ursusInputChrome(cornerRadius: 16, horizontalPadding: 12, verticalPadding: 12)

                    templateValidationMessages

                    HStack(spacing: 10) {
                        Button("Save Template") {
                            model.saveTemplate()
                        }
                        .ursusButtonStyle(.softPrimary)
                        .disabled(model.templateValidation.hasErrors || !model.templateHasUnsavedChanges)

                        Button("Revert Changes") {
                            model.revertTemplateDraft()
                        }
                        .ursusButtonStyle()
                        .disabled(!model.templateHasUnsavedChanges)
                    }

                    if model.templateHasUnsavedChanges && model.templateStatusError == nil {
                        Text("Unsaved changes stay in the app until you save.")
                            .font(.caption)
                            .foregroundStyle(ursusTertiaryTextColor)
                    }

                    UrsusMessageStack(error: model.templateStatusError)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var limitsPanel: some View {
        UrsusPanel(
            title: "Read and Backup Limits",
            titleHelpText: "Ursus can create backups automatically before edits, or on demand through backup tools."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default discovery limit",
                        value: autosavingBinding(\.defaultDiscoveryLimitDraft),
                        range: 1...500,
                        helpText: "Maximum number of note summaries returned by the Find Notes and List Backups tools."
                    )
                    configurationValidationMessages(for: .defaultDiscoveryLimit)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Default snippet length",
                        value: autosavingBinding(\.defaultSnippetLengthDraft),
                        range: 1...2_000
                    )
                    configurationValidationMessages(for: .defaultSnippetLength)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    UrsusNumericFieldRow(
                        label: "Backup retention days",
                        value: autosavingBinding(\.backupRetentionDaysDraft),
                        range: 0...365                    )
                    configurationValidationMessages(for: .backupRetentionDays)
                }
            }
        }
    }

    private var appUpdatesPanel: some View {
        UrsusPanel(title: "App Updates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    Toggle(
                        "Check for updates automatically",
                        isOn: Binding(
                            get: { updaterController.automaticallyChecksForUpdates },
                            set: { updaterController.setAutomaticallyChecksForUpdates($0) }
                        )
                    )
                    .disabled(!updaterController.isConfigured)

                    Spacer()

                    Button("Check for Updates…") {
                        updaterController.checkForUpdates()
                    }
                    .ursusButtonStyle()
                    .disabled(!updaterController.isConfigured || !updaterController.canCheckForUpdates)
                }

                if let configurationNote = updaterController.configurationNote {
                    Text(configurationNote)
                        .font(.caption)
                        .foregroundStyle(ursusTertiaryTextColor)
                }
            }
        }
    }

    private func autosavingBinding<Value>(_ keyPath: ReferenceWritableKeyPath<UrsusAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                model[keyPath: keyPath] = newValue
                model.configurationDraftDidChange()
            }
        )
    }

    private func segmentedPreferenceField<Value: Hashable>(
        label: String,
        selection: Binding<Value>,
        options: [UrsusSegmentedOption<Value>]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ursusInlineLabelColor)

            UrsusMiniSegmentedControl(selection: selection, options: options)
        }
    }
    
    private func limitedTemplateText(_ text: String, maxLines: Int) -> String {
        let lines = text.components(separatedBy: .newlines)
        return lines.prefix(maxLines).joined(separator: "\n")
    }

    @ViewBuilder
    private var templateValidationMessages: some View {
        if !model.templateValidation.issues.isEmpty {
            UrsusIssueList(issues: model.templateValidation.issues)
        }
    }

    @ViewBuilder
    private func configurationValidationMessages(for field: BearAppConfigurationField) -> some View {
        let issues = model.configurationIssues(for: field)
        if !issues.isEmpty {
            UrsusIssueList(issues: issues)
        }
    }
}
