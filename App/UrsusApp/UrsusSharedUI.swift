import AppKit
import BearApplication
import BearCore
import SwiftUI

struct UrsusScrollSurface<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(
            UrsusScrollViewChrome(knobStyle: colorScheme == .dark ? .dark : .light)
        )
    }
}

enum UrsusSectionSurface {
    case plain
    case subtle
    case prominent
}

struct UrsusPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let titleHelpText: String?
    let titleAccessory: AnyView?
    let surface: UrsusSectionSurface
    let headerAccessory: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        titleHelpText: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleHelpText = titleHelpText
        self.titleAccessory = nil
        self.surface = surface
        self.headerAccessory = nil
        self.content = content()
    }

    init<TitleAccessory: View>(
        title: String,
        subtitle: String? = nil,
        titleHelpText: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder titleAccessory: () -> TitleAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleHelpText = titleHelpText
        self.titleAccessory = AnyView(titleAccessory())
        self.surface = surface
        self.headerAccessory = nil
        self.content = content()
    }

    init<HeaderAccessory: View>(
        title: String,
        subtitle: String? = nil,
        titleHelpText: String? = nil,
        surface: UrsusSectionSurface = .plain,
        @ViewBuilder headerAccessory: () -> HeaderAccessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.titleHelpText = titleHelpText
        self.titleAccessory = nil
        self.surface = surface
        self.headerAccessory = AnyView(headerAccessory())
        self.content = content()
    }

    var body: some View {
        if surface == .plain {
            VStack(alignment: .leading, spacing: 8) {
                panelHeader
                content
                    .padding(.top, 15)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if surface == .subtle {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UrsusPanelBackground(style: .subtle))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        } else {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(UrsusPanelBackground(style: .prominent))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var panelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let titleAccessory {
                        titleAccessory
                    }

                    if let titleHelpText {
                        UrsusHelpButton(text: titleHelpText)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let headerAccessory {
                Spacer(minLength: 12)
                headerAccessory
            }
        }
    }
}

struct UrsusPanelBackground: ShapeStyle {
    let style: UrsusSectionSurface

    init(style: UrsusSectionSurface = .subtle) {
        self.style = style
    }

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        switch style {
        case .plain:
            Color.clear
        case .subtle:
            Color.secondary.opacity(environment.colorScheme == .dark ? 0.08 : 0.045)
        case .prominent:
            Color.secondary.opacity(environment.colorScheme == .dark ? 0.13 : 0.07)
        }
    }
}

struct UrsusGroupedBlock<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(
        padding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct UrsusScreenHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(.title2, design: .default).weight(.black))
                .tracking(-1.0)

            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct UrsusRuntimeRestartGuidance: View {
    static let message = "Changes save automatically. Reload your MCP client to apply them. If the Remote MCP Bridge is running, restart it first."

    var body: some View {
        Text(Self.message)
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UrsusInfoRow: View {
    let label: String
    let value: String
    var compact = false
    var monospaced = false

    var body: some View {
        if compact {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 12)

                Text(value)
                    .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)

                Text(value)
                    .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private let ursusIntegerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .none
    formatter.allowsFloats = false
    return formatter
}()

private struct UrsusInputChrome: ViewModifier {
    let cornerRadius: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func ursusInputChrome(
        cornerRadius: CGFloat = 8,
        horizontalPadding: CGFloat = 10,
        verticalPadding: CGFloat = 6
    ) -> some View {
        modifier(
            UrsusInputChrome(
                cornerRadius: cornerRadius,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
        )
    }
}

struct UrsusNumericFieldRow: View {
    let label: String
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var disabled = false
    var readOnly = false
    var helpText: String?
    var showsHelpButton = true
    var fieldWidth: CGFloat = 80

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)

                if showsHelpButton, let helpText {
                    UrsusHelpButton(text: helpText)
                }
            }

            Spacer()

            if readOnly {
                Text("\(value.wrappedValue)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(UrsusPanelBackground(style: .subtle))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help(helpText ?? "")
            } else {
                TextField(label, value: value, formatter: ursusIntegerFormatter)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .ursusInputChrome()
                    .frame(width: fieldWidth)
                    .disabled(disabled)
                    .help(helpText ?? "")

                Stepper("", value: value, in: range)
                    .labelsHidden()
                    .disabled(disabled)
                    .help(helpText ?? "")
            }
        }
    }
}

private struct UrsusScrollViewChrome: NSViewRepresentable {
    let knobStyle: NSScroller.KnobStyle

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(from: nsView)
        }
    }

    private func configure(from view: NSView) {
        let scrollViews = candidateScrollViews(from: view)
        for scrollView in scrollViews {
            installCustomScroller(on: scrollView, axis: .vertical)
            installCustomScroller(on: scrollView, axis: .horizontal)

            scrollView.scrollerKnobStyle = knobStyle
            scrollView.verticalScroller?.knobStyle = knobStyle
            scrollView.horizontalScroller?.knobStyle = knobStyle
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private func candidateScrollViews(from view: NSView) -> [NSScrollView] {
        if let window = view.window, let contentView = window.contentView {
            let discovered = recursiveScrollViews(in: contentView)
            if !discovered.isEmpty {
                return discovered
            }
        }

        if let ancestor = ancestorScrollView(from: view) {
            return [ancestor]
        }

        return []
    }

    private func recursiveScrollViews(in root: NSView) -> [NSScrollView] {
        var results: [NSScrollView] = []

        if let scrollView = root as? NSScrollView {
            results.append(scrollView)
        }

        for subview in root.subviews {
            results.append(contentsOf: recursiveScrollViews(in: subview))
        }

        return results
    }

    private func ancestorScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view

        while let candidate = current {
            if let scrollView = candidate as? NSScrollView {
                return scrollView
            }

            if let enclosing = candidate.enclosingScrollView {
                return enclosing
            }

            current = candidate.superview
        }

        return nil
    }

    private func installCustomScroller(on scrollView: NSScrollView, axis: UrsusScrollerAxis) {
        let currentScroller: NSScroller? = switch axis {
        case .vertical:
            scrollView.verticalScroller
        case .horizontal:
            scrollView.horizontalScroller
        }

        guard let currentScroller else {
            return
        }

        if currentScroller is UrsusTintedScroller {
            currentScroller.knobStyle = knobStyle
            return
        }

        let replacement = UrsusTintedScroller(frame: currentScroller.frame)
        replacement.scrollerStyle = currentScroller.scrollerStyle
        replacement.controlSize = currentScroller.controlSize
        replacement.knobStyle = knobStyle
        replacement.isEnabled = currentScroller.isEnabled
        replacement.doubleValue = currentScroller.doubleValue
        replacement.knobProportion = currentScroller.knobProportion
        replacement.target = currentScroller.target
        replacement.action = currentScroller.action

        switch axis {
        case .vertical:
            scrollView.verticalScroller = replacement
        case .horizontal:
            scrollView.horizontalScroller = replacement
        }
    }
}

private enum UrsusScrollerAxis {
    case vertical
    case horizontal
}

private final class UrsusTintedScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool {
        self == UrsusTintedScroller.self
    }

    override func drawKnob() {
        let knobRect = rect(for: .knob)
        guard !knobRect.isEmpty else {
            return
        }

        let drawRect = knobRect.insetBy(dx: knobInsetX, dy: knobInsetY)
        let radius = min(drawRect.width, drawRect.height) / 2
        let path = NSBezierPath(roundedRect: drawRect, xRadius: radius, yRadius: radius)

        knobColor.setFill()
        path.fill()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        let drawRect = slotRect.insetBy(dx: slotInsetX, dy: slotInsetY)
        guard drawRect.width > 0, drawRect.height > 0 else {
            return
        }

        let radius = min(drawRect.width, drawRect.height) / 2
        let path = NSBezierPath(roundedRect: drawRect, xRadius: radius, yRadius: radius)

        slotColor.setFill()
        path.fill()
    }

    private var isVerticalScroller: Bool {
        bounds.height >= bounds.width
    }

    private var knobInsetX: CGFloat {
        isVerticalScroller ? 2.5 : 1.5
    }

    private var knobInsetY: CGFloat {
        isVerticalScroller ? 1.5 : 2.5
    }

    private var slotInsetX: CGFloat {
        isVerticalScroller ? 4 : 2
    }

    private var slotInsetY: CGFloat {
        isVerticalScroller ? 2 : 4
    }

    private var usesDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var knobColor: NSColor {
        if usesDarkAppearance {
            return NSColor(calibratedWhite: 0.62, alpha: 0.52)
        }

        return NSColor(calibratedWhite: 0.35, alpha: 0.45)
    }

    private var slotColor: NSColor {
        if usesDarkAppearance {
            return NSColor(calibratedWhite: 1.0, alpha: 0.08)
        }

        return NSColor(calibratedWhite: 0.0, alpha: 0.07)
    }
}

struct UrsusHelpButton: View {
    let text: String
    @State private var showsPopover = false

    var body: some View {
        Button {
            showsPopover.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 240, alignment: .leading)
                .padding(14)
        }
    }
}

struct UrsusStatusBadge: View {
    let title: String
    let status: BearDoctorCheckStatus

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusPalette(for: status).background)
            .foregroundStyle(statusPalette(for: status).foreground)
            .clipShape(Capsule())
    }
}

struct UrsusConfiguredMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}

struct UrsusIssueList: View {
    private let rows: [IssueRow]

    init(issues: [BearAppConfigurationIssue]) {
        rows = issues.map {
            IssueRow(id: $0.id, severity: $0.severity, message: $0.message)
        }
    }

    init(issues: [BearTemplateValidationIssue]) {
        rows = issues.map {
            IssueRow(
                id: $0.id,
                severity: $0.severity == .error ? .error : .warning,
                message: $0.message
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows) { issue in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.severity == .error ? statusPalette(for: .failed).foreground : statusPalette(for: .notConfigured).foreground)
                        .padding(.top, 1)

                    Text(issue.message)
                        .font(.caption)
                        .foregroundStyle(issue.severity == .error ? statusPalette(for: .failed).foreground : statusPalette(for: .notConfigured).foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct IssueRow: Identifiable {
        let id: String
        let severity: BearAppConfigurationIssueSeverity
        let message: String
    }
}

struct UrsusMessageStack: View {
    let success: String?
    let warning: String?
    let error: String?

    private var hasContent: Bool {
        success != nil || warning != nil || error != nil
    }

    var body: some View {
        Group {
            if hasContent {
                VStack(alignment: .leading, spacing: 6) {
                    if let success {
                        UrsusFeedbackRow(symbol: "checkmark.circle", message: success, tone: .neutral)
                    }

                    if let warning, warning != success {
                        UrsusFeedbackRow(symbol: "exclamationmark.triangle.fill", message: warning, tone: .warning)
                    }

                    if let error {
                        UrsusFeedbackRow(symbol: "xmark.octagon.fill", message: error, tone: .error)
                    }
                }
            }
        }
    }
}

private enum UrsusFeedbackTone {
    case neutral
    case warning
    case error
}

private struct UrsusFeedbackRow: View {
    let symbol: String
    let message: String
    let tone: UrsusFeedbackTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(feedbackStyle)
                .padding(.top, 1)

            Text(message)
                .font(.callout)
                .foregroundStyle(feedbackStyle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var feedbackStyle: AnyShapeStyle {
        switch tone {
        case .neutral:
            return AnyShapeStyle(.secondary)
        case .warning:
            return AnyShapeStyle(statusPalette(for: .notConfigured).foreground)
        case .error:
            return AnyShapeStyle(statusPalette(for: .failed).foreground)
        }
    }
}

struct UrsusTagEditor: View {
    let tags: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if tags.isEmpty {
                Text("New notes stay untagged until you add one here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            onRemove(tag)
                        } label: {
                            HStack(spacing: 8) {
                                Text(tag)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "xmark")
                                    .font(.caption.weight(.bold))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(UrsusPanelBackground(style: .subtle))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Add default inbox tag", text: $draft)
                    .textFieldStyle(.plain)
                    .ursusInputChrome()
                    .submitLabel(.done)
                    .onSubmit(addDraft)

                Button("Add Tag") {
                    addDraft()
                }
                .buttonStyle(.bordered)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        onAdd(trimmed)
        draft = ""
    }
}

@ViewBuilder
func unavailablePanel(title: String, detail: String) -> some View {
    UrsusPanel(title: title, subtitle: detail, surface: .subtle) {
        EmptyView()
    }
}

func launcherPrimaryActionTitle(for settings: BearAppSettingsSnapshot) -> String? {
    switch settings.launcherStatus {
    case .missing:
        return "Install Launcher"
    case .invalid:
        return "Repair Launcher"
    case .ok, .configured, .notConfigured, .failed:
        return nil
    }
}

func compactStatusTitle(for status: BearDoctorCheckStatus) -> String {
    switch status {
    case .ok, .configured:
        return "Ready"
    case .missing, .notConfigured:
        return "Set up"
    case .invalid, .failed:
        return "Needs attention"
    }
}

func statusPalette(for status: BearDoctorCheckStatus) -> (foreground: Color, background: Color) {
    switch status {
    case .ok, .configured:
        return (
            foreground: Color.mint,
            background: Color.mint.opacity(0.12)
        )
    case .missing, .notConfigured:
        return (
            foreground: Color.orange,
            background: Color.orange.opacity(0.1)
        )
    case .invalid, .failed:
        return (
            foreground: Color.red,
            background: Color.red.opacity(0.1)
        )
    }
}
