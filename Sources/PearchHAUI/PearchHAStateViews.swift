import SwiftUI
import PearchHACore

/// The uppercase, muted section/room label shared by the panel room headers and
/// the settings sections, with an optional leading SF Symbol and optional
/// trailing action control.
///
/// The label is tracked, single-line, and `secondary`-tinted. Callers keep their
/// own accessibility framing by passing the same `title`; this view exposes the
/// title as its accessibility label and ignores the decorative glyph.
public struct PearchHASectionHeader<Trailing: View>: View {
    private let title: String
    private let systemImage: String?
    private let trailing: Trailing

    /// Creates a section header.
    ///
    /// - Parameters:
    ///   - title: The label text, rendered uppercased.
    ///   - systemImage: An optional leading SF Symbol tinted to the accent.
    ///   - trailing: An optional trailing action control (e.g. a button).
    public init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: PearchHASpacing.xs + 1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(PearchHATypography.caption())
                    .foregroundStyle(PearchHATheme.accent)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(PearchHATypography.caption())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .lineLimit(1)
            Spacer(minLength: 0)
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

public extension PearchHASectionHeader where Trailing == EmptyView {
    /// Creates a section header with no trailing control.
    ///
    /// - Parameters:
    ///   - title: The label text, rendered uppercased.
    ///   - systemImage: An optional leading SF Symbol tinted to the accent.
    init(_ title: String, systemImage: String? = nil) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

/// A consistent, centered placeholder state (SF Symbol + title + message + an
/// optional action) shared by the loading, empty, error, and permission views.
///
/// Built on the design tokens so spacing and typography match the rest of the
/// app. The whole view is a single accessibility element labelled with the
/// title and message; the decorative symbol is hidden from assistive tech.
public struct PearchHAStateView: View {
    /// How prominent the symbol and layout should be.
    public enum Emphasis: Equatable, Sendable {
        /// A full-bleed centered state for an otherwise empty content area.
        case prominent
        /// A compact, leading-aligned inline state for use inside a form or row.
        case inline
    }

    private let systemImage: String
    private let symbolTint: Color
    private let title: String
    private let message: String?
    private let emphasis: Emphasis
    private let isProgress: Bool
    private let actionTitle: String?
    private let actionSystemImage: String?
    private let actionDisabled: Bool
    private let action: (() -> Void)?

    /// Creates a state view.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol shown above (or before) the text.
    ///   - symbolTint: The tint for the symbol. Defaults to `secondary`.
    ///   - title: The headline line.
    ///   - message: An optional supporting line.
    ///   - emphasis: Layout prominence; defaults to ``Emphasis/prominent``.
    ///   - isProgress: When `true`, an indeterminate spinner replaces the symbol.
    ///   - actionTitle: The optional action button's title.
    ///   - actionSystemImage: The optional action button's SF Symbol.
    ///   - actionDisabled: Whether the action button is disabled.
    ///   - action: The action performed when the button is pressed.
    public init(
        systemImage: String,
        symbolTint: Color = .secondary,
        title: String,
        message: String? = nil,
        emphasis: Emphasis = .prominent,
        isProgress: Bool = false,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.symbolTint = symbolTint
        self.title = title
        self.message = message
        self.emphasis = emphasis
        self.isProgress = isProgress
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.actionDisabled = actionDisabled
        self.action = action
    }

    public var body: some View {
        switch emphasis {
        case .prominent:
            prominentBody
        case .inline:
            inlineBody
        }
    }

    private var prominentBody: some View {
        VStack(spacing: PearchHASpacing.md) {
            Spacer(minLength: 0)
            symbol(size: 34)
            VStack(spacing: PearchHASpacing.xs) {
                Text(title)
                    .font(.headline)
                if let message {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            actionButton
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(PearchHASpacing.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    private var inlineBody: some View {
        HStack(alignment: .top, spacing: PearchHASpacing.sm) {
            symbol(size: 13)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(symbolTint)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actionButton
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private func symbol(size: CGFloat) -> some View {
        if isProgress {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: size))
                .foregroundStyle(symbolTint)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let actionTitle, let action {
            Button(action: action) {
                if let actionSystemImage {
                    Label(actionTitle, systemImage: actionSystemImage)
                } else {
                    Text(actionTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(actionDisabled)
        }
    }

    private var accessibilityText: String {
        guard let message else {
            return title
        }
        return "\(title). \(message)"
    }
}

/// A loading state shown while connecting or before the first values arrive.
public struct PearchHALoadingState: View {
    private let title: String
    private let message: String?

    /// Creates a loading state.
    ///
    /// - Parameters:
    ///   - title: The headline (e.g. "Connecting…").
    ///   - message: An optional supporting line.
    public init(title: String, message: String? = nil) {
        self.title = title
        self.message = message
    }

    public var body: some View {
        PearchHAStateView(
            systemImage: "hourglass",
            title: title,
            message: message,
            isProgress: true
        )
    }
}

/// A "nothing here yet" state with an optional call-to-action.
public struct PearchHAEmptyState: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let actionSystemImage: String?
    private let actionDisabled: Bool
    private let action: (() -> Void)?

    /// Creates an empty state.
    ///
    /// - Parameters:
    ///   - systemImage: The SF Symbol shown above the text.
    ///   - title: The headline.
    ///   - message: An optional supporting line.
    ///   - actionTitle: The optional action button's title.
    ///   - actionSystemImage: The optional action button's SF Symbol.
    ///   - actionDisabled: Whether the action button is disabled.
    ///   - action: The action performed when the button is pressed.
    public init(
        systemImage: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        actionDisabled: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.actionDisabled = actionDisabled
        self.action = action
    }

    public var body: some View {
        PearchHAStateView(
            systemImage: systemImage,
            title: title,
            message: message,
            actionTitle: actionTitle,
            actionSystemImage: actionSystemImage,
            actionDisabled: actionDisabled,
            action: action
        )
    }
}

/// An error state tinted to the critical color, with an optional retry action.
///
/// The ``Style`` controls whether the error is a full-bleed centered state or a
/// compact inline banner suitable for placement inside a form.
public struct PearchHAErrorState: View {
    /// The presentation style of the error.
    public enum Style: Equatable, Sendable {
        /// A full-bleed centered error state.
        case prominent
        /// A compact inline error banner.
        case inline
    }

    private let title: String
    private let message: String?
    private let style: Style
    private let accessibilityPrefix: String?
    private let actionTitle: String?
    private let actionSystemImage: String?
    private let action: (() -> Void)?

    /// Creates an error state.
    ///
    /// - Parameters:
    ///   - title: The primary error line.
    ///   - message: An optional supporting hint.
    ///   - style: The presentation style; defaults to ``Style/inline``.
    ///   - accessibilityPrefix: An optional spoken prefix (e.g. "Connection
    ///     error") prepended to the accessibility label.
    ///   - actionTitle: The optional retry button's title.
    ///   - actionSystemImage: The optional retry button's SF Symbol.
    ///   - action: The action performed when the retry button is pressed.
    public init(
        title: String,
        message: String? = nil,
        style: Style = .inline,
        accessibilityPrefix: String? = nil,
        actionTitle: String? = nil,
        actionSystemImage: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.accessibilityPrefix = accessibilityPrefix
        self.actionTitle = actionTitle
        self.actionSystemImage = actionSystemImage
        self.action = action
    }

    public var body: some View {
        PearchHAStateView(
            systemImage: "exclamationmark.triangle.fill",
            symbolTint: style == .inline ? PearchHATheme.critical : PearchHATheme.critical,
            title: title,
            message: message,
            emphasis: style == .inline ? .inline : .prominent,
            actionTitle: actionTitle,
            actionSystemImage: actionSystemImage,
            action: action
        )
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = message.map { "\(title). \($0)" } ?? title
        guard let accessibilityPrefix else {
            return base
        }
        return "\(accessibilityPrefix): \(base)"
    }
}

/// A calm permission state for an action the system declined (e.g. enabling
/// launch at login), with guidance on where to grant it.
public struct PearchHAPermissionState: View {
    private let title: String
    private let message: String
    private let systemImage: String

    /// Creates a permission state.
    ///
    /// - Parameters:
    ///   - title: The primary line (e.g. "Couldn't enable launch at login").
    ///   - message: Where to grant the permission in System Settings.
    ///   - systemImage: The SF Symbol; defaults to a lock badge.
    public init(
        title: String,
        message: String,
        systemImage: String = "lock.trianglebadge.exclamationmark"
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
    }

    public var body: some View {
        PearchHAStateView(
            systemImage: systemImage,
            symbolTint: PearchHATheme.warn,
            title: title,
            message: message,
            emphasis: .inline
        )
    }
}

/// A small, non-interactive live preview of how the menu-bar item and a popover
/// row will look under the current appearance, accent, and theme preferences.
///
/// Drives entirely off the passed ``PearchHADisplayPreferences`` and does no data
/// fetching, so a preference change re-renders it immediately. The preview is a
/// single accessibility element describing the rendered configuration.
public struct PearchHAAppearancePreview: View {
    @Environment(\.colorScheme) private var colorScheme
    private let preferences: PearchHADisplayPreferences

    /// Creates the appearance preview.
    ///
    /// - Parameter preferences: The display preferences to visualize.
    public init(preferences: PearchHADisplayPreferences) {
        self.preferences = preferences
    }

    private var accent: Color {
        Color(
            .sRGB,
            red: preferences.accentColor.red,
            green: preferences.accentColor.green,
            blue: preferences.accentColor.blue,
            opacity: preferences.accentColor.alpha
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PearchHASpacing.sm) {
            menuBarSample
            popoverRowSample
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var menuBarSample: some View {
        HStack(spacing: PearchHASpacing.sm) {
            HStack(spacing: PearchHASpacing.xs + 1) {
                if preferences.menuBarAppearance.showsImage {
                    Image(systemName: "thermometer.medium")
                        .font(PearchHATypography.caption())
                        .foregroundStyle(accent)
                }
                if preferences.menuBarAppearance.showsTitle {
                    Text("21°")
                        .font(
                            preferences.stableMenuBarWidth
                                ? PearchHATypography.bodyValue()
                                : PearchHATypography.body()
                        )
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, PearchHASpacing.sm)
            .padding(.vertical, PearchHASpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: PearchHACornerRadius.control - 2, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            Spacer(minLength: 0)
        }
    }

    private var popoverRowSample: some View {
        let shape = RoundedRectangle(cornerRadius: PearchHACornerRadius.card, style: .continuous)
        return HStack(spacing: PearchHASpacing.sm) {
            Image(systemName: "thermometer.medium")
                .font(PearchHATypography.body())
                .foregroundStyle(accent)
                .frame(width: 22)
            Text("Living Room")
                .font(PearchHATypography.body())
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Text("21°")
                .font(PearchHATypography.bodyValue())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PearchHASpacing.md)
        .padding(.vertical, PearchHASpacing.sm)
        .background(PearchHATheme.cardFill(colorScheme), in: shape)
        .overlay(shape.strokeBorder(PearchHATheme.cardBorder(colorScheme), lineWidth: 1))
    }

    private var accessibilityText: String {
        "Preview: menu bar shows \(preferences.menuBarAppearance.displayName.lowercased()), and a sample popover row."
    }
}

/// The placeholder state that applies to a panel content area for a given phase.
///
/// A pure mapping from ``PearchHAPanelPhase`` to the kind of state view the panel
/// content should present, extracted so the selection is unit-testable without
/// rendering SwiftUI. `.data` means real room content (no placeholder).
public enum PearchHAStateViewKind: Equatable, Sendable {
    /// Connecting or awaiting the first values: show a loading state.
    case loading
    /// Connected with no selected values: show an empty state.
    case empty
    /// Hard failure with no stale values to show: show the connection form.
    case connectionForm
    /// Real room content (possibly stale): show the data list.
    case data

    /// The placeholder kind for a panel phase.
    ///
    /// - Parameter phase: The current panel phase.
    /// - Returns: The state-view kind the content area should present.
    public static func forContent(phase: PearchHAPanelPhase) -> PearchHAStateViewKind {
        switch phase {
        case .connecting:
            .loading
        case .connectedEmpty:
            .empty
        case .firstRun, .failed:
            .connectionForm
        case .connectedData, .reconnecting, .failedStale:
            .data
        }
    }
}
