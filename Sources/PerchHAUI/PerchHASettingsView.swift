import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

/// Connection form field stack shared by the menu-bar panel's first-run view and
/// the Settings window's Connection tab.
///
/// The shared fields cover the Home Assistant URL, fallback URL, access token,
/// the failure/progress banners, the sign-in/connect buttons, and an explicit
/// self-signed certificate opt-in scoped to the entered HTTPS hosts.
/// Certificate validation stays strict unless the user opts in.
struct PerchHAConnectionFormFields: View {
    @ObservedObject var model: PerchHAPanelModel

    var body: some View {
        if showsConnectedState {
            connectedState
        } else {
            editableFields
        }
    }

    private var editableFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Connect to Home Assistant")
                    .font(.headline)
                Text("Enter your Home Assistant address, then sign in or paste an access token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            connectionStatusBanner

            addressList

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    model.startOAuthSignIn()
                } label: {
                    Label(oauthSignInButtonTitle, systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnectionBusy)
                .help("Open Home Assistant in your browser to sign in. Recommended.")
                Text("Opens Home Assistant in your browser to approve access. No password is stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                line
                Text("or use an access token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                line
            }

            VStack(alignment: .leading, spacing: 4) {
                PerchHANativeSecureField(
                    placeholder: "Access token",
                    text: tokenBinding,
                    contentType: .password
                )
                Text("Create one in Home Assistant under your profile → Security → Long-lived access tokens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Where to find a token: Home Assistant profile, Security, Long-lived access tokens.")
                Button("Connect with token") {
                    model.startConnect()
                }
                .buttonStyle(.bordered)
                .disabled(isConnectionBusy)
            }

        }
    }

    /// The editable, ordered list of Home Assistant addresses.
    ///
    /// The primary address is first (the URL the connected state derives its host
    /// from); each alternative carries an optional label plus URL with move/remove
    /// controls, plus an "Add address" affordance. Invalid alternatives surface a
    /// calm inline error so paste-and-fix stays low-friction.
    private var addressList: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Primary address")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PerchHANativeTextField(
                    placeholder: "Home Assistant URL",
                    text: urlBinding,
                    contentType: {
                        if #available(macOS 14.0, *) {
                            return .URL
                        }
                        return nil
                    }(),
                    normalizeOnCommit: PerchHAConnectionForm.normalizedHomeAssistantURLString
                )
            }

            ForEach(Array(model.snapshot.connectionForm.addresses.enumerated()), id: \.element.id) { index, address in
                alternativeAddressRow(address, index: index)
            }

            Button {
                model.addConnectionAddress()
            } label: {
                Label("Add address", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint("Adds another Home Assistant address to try")

            Text("Add internal, external, or VPN addresses. They are tried in order when an earlier one cannot be reached.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            selfSignedCertificateOptIn
        }
    }

    /// The self-signed certificate switch. Always visible and editable so the
    /// trust posture can be changed at any time, connected or not.
    private var selfSignedCertificateOptIn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(
                "Trust self-signed certificates for these addresses",
                isOn: Binding(
                    get: { model.snapshot.connectionForm.allowsSelfSignedCertificates },
                    set: { model.updateConnectionForm(allowsSelfSignedCertificates: $0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            Text("Applies only to the HTTPS addresses listed above — never to other hosts. Turn off for strict certificate validation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityHint("Allows self-signed TLS certificates for the Home Assistant addresses in this form only")
    }

    private func alternativeAddressRow(_ address: PerchHAConnectionAddressField, index: Int) -> some View {
        let count = model.snapshot.connectionForm.addresses.count
        let invalid = !address.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && address.validURL == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PerchHANativeTextField(
                    placeholder: "Label (optional)",
                    text: labelBinding(id: address.id),
                    contentType: nil,
                    normalizeOnCommit: { $0 }
                )
                .frame(width: 130)
                PerchHANativeTextField(
                    placeholder: "Alternative URL",
                    text: addressURLBinding(id: address.id),
                    contentType: {
                        if #available(macOS 14.0, *) {
                            return .URL
                        }
                        return nil
                    }(),
                    normalizeOnCommit: PerchHAConnectionForm.normalizedHomeAssistantURLString
                )
                Button {
                    model.moveConnectionAddress(id: address.id, direction: .up)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(index == 0)
                .accessibilityLabel("Move address up")
                Button {
                    model.moveConnectionAddress(id: address.id, direction: .down)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(index == count - 1)
                .accessibilityLabel("Move address down")
                Button(role: .destructive) {
                    model.removeConnectionAddress(id: address.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove address")
            }
            if invalid {
                Text("Enter a valid http or https address.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Invalid alternative address")
            }
        }
    }

    /// True when the app is connected or holds an active stored auth session, so
    /// the form should present the compact connected state instead of blank
    /// login fields.
    private var showsConnectedState: Bool {
        if model.snapshot.showsConnectedContent {
            return true
        }
        switch model.snapshot.connectionState {
        case .connected, .reconnecting:
            return true
        case .connecting, .disconnected, .failed:
            return false
        }
    }

    /// The host shown in the connected state, derived from the real stored
    /// connection URL (not a blanked editing binding).
    private var connectedHost: String? {
        let urlString = model.snapshot.connectionForm.urlString
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            return host
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var connectedState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text("Connected")
                        .font(.headline)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(connectedAccessibilityLabel)
                if let connectedHost {
                    Text("Connected to \(connectedHost)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }

            connectionStatusBanner

            addressList

            HStack(spacing: 8) {
                Button("Update connection") {
                    model.applyConnectionEdits()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnectionBusy || !model.canApplyConnectionEdits)
                .help("Reconnect using your saved session and the addresses above.")

                Button("Sign out") {
                    model.signOut()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Disconnect and clear the stored session. The address is kept so you can reconnect.")
            }
        }
    }

    private var connectedAccessibilityLabel: String {
        if let connectedHost {
            return "Connected to \(connectedHost)"
        }
        return "Connected"
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        if let failureDescription = model.snapshot.failureDescription {
            connectionMessage(
                failureDescription,
                hint: connectionFailureHint(failureDescription),
                accessibilityPrefix: "Connection error"
            )
        }
        if let oauthFailureDescription {
            connectionMessage(
                oauthFailureDescription,
                hint: connectionFailureHint(oauthFailureDescription),
                accessibilityPrefix: "Sign-in error"
            )
        }
        if let connectionProgressMessage {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .accessibilityHidden(true)
                Text(connectionProgressMessage)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(connectionProgressMessage)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func connectionMessage(
        _ message: String,
        hint: String?,
        accessibilityPrefix: String
    ) -> some View {
        PerchHAErrorState(
            title: message,
            message: hint,
            style: .inline,
            accessibilityPrefix: accessibilityPrefix
        )
    }

    private func connectionFailureHint(_ message: String) -> String? {
        let lowered = message.lowercased()
        if lowered.contains("auth") || lowered.contains("token") || lowered.contains("401") {
            return "Check your access token, or use Sign in instead."
        }
        if lowered.contains("unreachable") || lowered.contains("could not") || lowered.contains("connect") || lowered.contains("host") {
            return "Check the Home Assistant address and that this Mac can reach it."
        }
        if lowered.contains("tls") || lowered.contains("certificate") || lowered.contains("ssl") {
            return "Check the Home Assistant address and that this Mac can reach it."
        }
        return nil
    }

    private var oauthFailureDescription: String? {
        if case let .failed(message) = model.oauthSignInState {
            return message
        }
        return nil
    }

    private var oauthSignInButtonTitle: String {
        model.oauthSignInState == .signingIn ? "Signing in..." : "Sign in"
    }

    private var connectionProgressMessage: String? {
        if model.oauthSignInState == .signingIn {
            return "Signing in"
        }
        if model.snapshot.connectionState == .connecting {
            return "Connecting to Home Assistant"
        }
        return nil
    }

    private var isConnectionBusy: Bool {
        model.snapshot.connectionState == .connecting || model.oauthSignInState == .signingIn
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { model.snapshot.connectionForm.urlString },
            set: { value in
                model.updateConnectionForm(urlString: value)
            }
        )
    }

    private func labelBinding(id: PerchHAConnectionAddressField.ID) -> Binding<String> {
        Binding(
            get: { model.snapshot.connectionForm.addresses.first { $0.id == id }?.label ?? "" },
            set: { value in
                model.updateConnectionAddress(id: id, label: value)
            }
        )
    }

    private func addressURLBinding(id: PerchHAConnectionAddressField.ID) -> Binding<String> {
        Binding(
            get: { model.snapshot.connectionForm.addresses.first { $0.id == id }?.urlString ?? "" },
            set: { value in
                model.updateConnectionAddress(id: id, urlString: value)
            }
        )
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: { model.tokenInputForView },
            set: { value in
                model.updateConnectionForm(token: value)
            }
        )
    }
}

/// Dedicated, resizable Settings window content for PerchHA.
///
/// Organized as a `TabView` with three tabs: Connection, Entities, and About.
/// Per-entity display and action configuration stays inline inside the
/// Entities tree, matching the documented UX. This view hosts the settings-only
/// controls relocated out of the cramped menu-bar panel.
public struct PerchHASettingsView: View {
    /// Selectable sections of the Settings window, shown in the sidebar rail in
    /// declaration order.
    public enum Tab: Hashable, Sendable, CaseIterable {
        case general
        case connection
        case entities
        case appearance
        case diagnostics
        case privacy
        case about

        /// The sidebar rail label.
        var title: String {
            switch self {
            case .general: "General"
            case .connection: "Connection"
            case .entities: "Entities"
            case .appearance: "Appearance"
            case .diagnostics: "Diagnostics"
            case .privacy: "Privacy"
            case .about: "About"
            }
        }

        /// The sidebar rail SF Symbol.
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .connection: "network"
            case .entities: "square.grid.2x2"
            case .appearance: "paintbrush"
            case .diagnostics: "stethoscope"
            case .privacy: "lock"
            case .about: "info.circle"
            }
        }
    }

    @ObservedObject private var model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    private let displayPreferencesProvider: () -> PerchHADisplayPreferences
    private let displayPreferencesSink: (PerchHADisplayPreferences) -> Void
    private let launchAtLoginProvider: () -> Bool
    private let launchAtLoginSink: (Bool) -> Bool
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var selectedTab: Tab
    /// The single entity whose inspector is open in the Entities tab, or `nil`
    /// when every row is collapsed. Only one inspector is open at a time.
    @State private var inspectedEntityID: EntityID?
    /// Room ids (``RoomID/rawValue``) whose entity rows are collapsed in the
    /// Entities tab. Rooms default to expanded, so a room is hidden only when it
    /// appears here. A live search or an open inspector force the affected room
    /// visible regardless of this set, without mutating it, so clearing the
    /// search restores the prior collapsed state.
    @State private var collapsedRooms: Set<String> = []
    @State private var displayPreferences: PerchHADisplayPreferences
    /// View-local echo of the Entities search field; pushed to the model after
    /// a short debounce so typing never rebuilds the whole app state per key.
    @State private var entitySearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var launchAtLogin: Bool
    @State private var launchAtLoginPermissionDenied = false
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    /// Creates the Settings window content.
    ///
    /// - Parameters:
    ///   - model: The shared panel model driving every binding and persistence
    ///     side effect.
    ///   - accessibilityPreferencesOverride: Optional fixed accessibility
    ///     preferences. When `nil`, preferences are read from the environment.
    ///   - initialTab: The tab shown when the window first appears.
    ///   - initiallyExpandedEntityIDs: Entity rows in the Entities tab whose
    ///     per-entity configuration should be disclosed (expanded) on first
    ///     render. Defaults to empty, so every row starts collapsed. Used by
    ///     snapshot and test render paths to reveal the configuration controls
    ///     of the entity under inspection.
    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil,
        initialTab: Tab = .connection,
        initiallyExpandedEntityIDs: Set<EntityID> = [],
        displayPreferencesProvider: @escaping () -> PerchHADisplayPreferences = { .defaults },
        displayPreferencesSink: @escaping (PerchHADisplayPreferences) -> Void = { _ in },
        launchAtLoginProvider: @escaping () -> Bool = { false },
        launchAtLoginSink: @escaping (Bool) -> Bool = { _ in false }
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        self.displayPreferencesProvider = displayPreferencesProvider
        self.displayPreferencesSink = displayPreferencesSink
        self.launchAtLoginProvider = launchAtLoginProvider
        self.launchAtLoginSink = launchAtLoginSink
        _selectedTab = State(initialValue: initialTab)
        // Only one entity inspector is open at a time; seed it from the first
        // requested expansion (used by snapshot/test render paths).
        _inspectedEntityID = State(initialValue: initiallyExpandedEntityIDs.first)
        _displayPreferences = State(initialValue: displayPreferencesProvider())
        _launchAtLogin = State(initialValue: launchAtLoginProvider())
    }

    public var body: some View {
        let accessibility = PerchHAPanelView.rootAccessibilityPresentation(
            snapshot: model.snapshot,
            preferences: accessibilityPreferences
        )
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: 0) {
            sidebarRail
            Rectangle()
                .fill(palette.separatorSubtle)
                .frame(width: 1)
                .accessibilityHidden(true)
            detailContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.surfaceRoot.ignoresSafeArea())
        }
        .environment(\.dashboardPalette, palette)
        .frame(minWidth: 660, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(PerchHATheme.accent)
        .contrast(accessibility.contrastPolicy == .increased ? 1.12 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .transaction { transaction in
            if accessibility.motionPolicy == .reduced {
                transaction.animation = nil
            }
        }
    }

    /// The deterministic left sidebar rail: a fixed-width vertical stack of one
    /// selectable row per ``Tab`` case, in declaration order. Unlike
    /// `NavigationSplitView`, this plain `HStack` rail always renders and never
    /// auto-collapses in the fixed-size Settings window. Each row is a focusable
    /// `Button` carrying a spoken accessibility name; the selected row is
    /// highlighted with the palette accent (filled rounded background, accent
    /// text) and marked with the selected trait. The rail sits on the palette's
    /// elevated surface so it reads as a rail in both light and dark.
    private var sidebarRail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, PerchHASpacing.sm)
            .padding(.vertical, PerchHASpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 198)
        .frame(maxHeight: .infinity)
        .background(railBackground.ignoresSafeArea())
        .accessibilityLabel("Settings sections")
    }

    /// A single selectable rail row: SF Symbol + label in a full-width tappable
    /// `Button`. The selected row fills with the accent and uses accent text;
    /// unselected rows use secondary text.
    private func sidebarRow(_ tab: Tab) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: PerchHASpacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isSelected ? palette.accentPrimary : palette.textSecondary)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? palette.textPrimary : palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PerchHASpacing.sm)
            .padding(.vertical, PerchHASpacing.sm - 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(isSelected ? palette.accentPrimary.opacity(colorScheme == .dark ? 0.22 : 0.14) : Color.clear)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(isSelected ? palette.accentPrimary : Color.clear)
                    .frame(width: 3, height: 16)
                    .offset(x: -PerchHASpacing.xs)
            }
            .contentShape(RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The rail's surface fill, resolved against the current appearance so it
    /// reads as a distinct rail that matches the dashboard panel in light/dark.
    private var railBackground: Color {
        PerchHATheme.Dashboard.palette(colorScheme).surfacePanel
    }

    /// Routes a section to its detail content.
    @ViewBuilder
    private func detailContent(for tab: Tab) -> some View {
        switch tab {
        case .general: generalTab
        case .connection: connectionTab
        case .entities: entitiesTab
        case .appearance: appearanceTab
        case .diagnostics: diagnosticsTab
        case .privacy: privacyTab
        case .about: aboutTab
        }
    }

    private var accessibilityPreferences: PerchHAAccessibilityPreferences {
        if let accessibilityPreferencesOverride {
            return accessibilityPreferencesOverride
        }
        return PerchHAAccessibilityPreferences(
            reduceMotion: accessibilityReduceMotion,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    /// Renders a single tab's content (without the surrounding `TabView` chrome)
    /// on an opaque full-bleed background. Used to capture deterministic settings
    /// snapshots that avoid the platform tab-strip's transparent regions.
    @ViewBuilder
    public func tabContentForSnapshot(_ tab: Tab) -> some View {
        let content: AnyView = switch tab {
        case .general: AnyView(generalTab)
        case .connection: AnyView(connectionTab)
        case .entities: AnyView(entitiesTab)
        case .appearance: AnyView(appearanceTab)
        case .diagnostics: AnyView(diagnosticsTab)
        case .privacy: AnyView(privacyTab)
        case .about: AnyView(aboutTab)
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(PerchHATheme.Dashboard.palette(colorScheme).surfaceRoot.ignoresSafeArea())
            .environment(\.dashboardPalette, PerchHATheme.Dashboard.palette(colorScheme))
            .contrast(accessibilityPreferences.contrastPolicy == .increased ? 1.12 : 1)
    }

    private var connectionTab: some View {
        settingsPage(title: "Connection", systemImage: Tab.connection.systemImage) {
            settingsCard {
                settingsSection(title: "Status", systemImage: "antenna.radiowaves.left.and.right") {
                    connectionStatusContent
                }
            }
            settingsCard {
                settingsSection(title: "Addresses & access", systemImage: "network") {
                    PerchHAConnectionFormFields(model: model)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    /// The connection status card content: a status pill, the connected host
    /// (when known), and the last successful update — all derived from the live
    /// snapshot. No stored secret is ever surfaced.
    private var connectionStatusContent: some View {
        let status = connectionDiagnostic
        let host = connectionSummaryHost
        return VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            HStack(spacing: 8) {
                StatusPill(
                    status.label,
                    systemImage: status.systemImage,
                    color: status.color,
                    accessibilityLabel: "Connection \(status.label)"
                )
                Spacer(minLength: 0)
            }
            if let host {
                settingsControlRow("Server") {
                    Text(host)
                        .font(PerchHATypography.bodyValue())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            settingsControlRow("Last update") {
                Text(model.snapshot.lastUpdateDescription)
                    .font(PerchHATypography.bodyValue())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The connected server host shown in the Connection status card, derived
    /// from the stored connection URL. Never exposes the access token.
    private var connectionSummaryHost: String? {
        let urlString = model.snapshot.connectionForm.urlString
        if let host = URL(string: urlString)?.host, !host.isEmpty {
            return host
        }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A page scaffold shared by every section: a leading-aligned scroll view
    /// hosting a section title and a vertical stack of grouped cards on the
    /// window background, with consistent design-token insets.
    @ViewBuilder
    private func settingsPage<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchHASpacing.md + 2) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, PerchHASpacing.lg)
            .padding(.horizontal, PerchHASpacing.lg + 2)
        }
        .toggleStyle(PerchHASwitchToggleStyle())
        .tint(PerchHATheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A grouped settings card styled with the dashboard palette: an elevated
    /// surface fill with a subtle hairline border and consistent interior
    /// padding, so settings share the dashboard's panel language and no raw
    /// ungrouped form rows are drawn anywhere.
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return VStack(alignment: .leading, spacing: PerchHASpacing.md) {
            content()
        }
        .padding(PerchHASpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .fill(palette.surfacePanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
    }

    /// A compact card variant used for inline inspectors and nested groups, with
    /// the slightly more elevated surface so it reads as sitting above a card.
    private func settingsInsetGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            content()
        }
        .padding(PerchHASpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                .fill(palette.surfacePanelElevated)
        )
    }

    // MARK: General

    /// General settings: the genuinely-global preferences that do not belong to a
    /// more specific section. Appearance (theme/accent) lives in the Appearance
    /// section, so it is intentionally not duplicated here.
    private var generalTab: some View {
        settingsPage(title: "General", systemImage: Tab.general.systemImage) {
            settingsCard {
                settingsSection(title: "Startup", systemImage: "power") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm - 2) {
                        Toggle("Launch at login", isOn: launchAtLoginBinding)
                            .fixedSize()
                            .accessibilityLabel("Launch PearchHA at login")
                        Text("Start PearchHA automatically when you sign in to this Mac.")
                            .font(PerchHATypography.caption().weight(.regular))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if launchAtLoginPermissionDenied {
                            PerchHAPermissionState(
                                title: "Couldn't enable launch at login",
                                message: "Open System Settings > General > Login Items and allow PearchHA."
                            )
                        }
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Keyboard", systemImage: "keyboard") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
                        shortcutRow(label: "Open settings", keys: "⌘ ,")
                        settingsSectionDivider
                        shortcutRow(label: "Quit PearchHA", keys: "⌘ Q")
                        Text("These shortcuts are built in and cannot be changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// A read-only row pairing a shortcut description with its key combination,
    /// shown as a calm keycap so it reads as a fact rather than an editable
    /// control (no editable shortcut binding exists today).
    private func shortcutRow(label: String, keys: String) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        return HStack(spacing: PerchHASpacing.sm) {
            Text(label)
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 8)
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(palette.surfaceControl)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(palette.borderSubtle, lineWidth: 1)
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), shortcut \(keys)")
    }

    // MARK: Appearance

    /// Appearance: the live preview plus the theme/accent controls, which share
    /// their bindings (and persistence) with the General section, and a reset to
    /// the shipped display-preference defaults.
    private var appearanceTab: some View {
        settingsPage(title: "Appearance", systemImage: Tab.appearance.systemImage) {
            settingsCard {
                settingsSection(title: "Preview", systemImage: "eye") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.md) {
                        PerchHAAppearancePreview(preferences: displayPreferences)
                        appearanceDashboardSample
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Theme & accent", systemImage: "paintbrush") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsControlRow("Theme") {
                            themeModePicker
                        }
                        settingsControlRow("Accent") {
                            accentMenuPicker
                        }
                        accentSwatchPreview
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Menu bar", systemImage: "menubar.rectangle") {
                    VStack(alignment: .leading, spacing: 10) {
                        settingsControlRow("Style") {
                            Picker("Menu bar style", selection: menuBarAppearanceBinding) {
                                ForEach(PerchHAMenuBarAppearance.allCases, id: \.rawValue) { appearance in
                                    Text(appearance.displayName).tag(appearance)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Global menu bar style")
                        }
                        Text("The default look for menu-bar values. Individual values can override this in Entities.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Keep a stable width", isOn: stableMenuBarWidthBinding)
                            .fixedSize()
                            .accessibilityLabel("Keep a stable menu bar width")
                        Text("Uses monospaced digits so the value does not shift as it changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Dashboard", systemImage: "rectangle.grid.1x2") {
                    VStack(alignment: .leading, spacing: PerchHASpacing.sm + 2) {
                        settingsControlRow("Row density") {
                            Picker("Row density", selection: rowDensityBinding) {
                                ForEach(PerchHADashboardRowDensity.allCases, id: \.rawValue) { density in
                                    Text(density.displayName).tag(density)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Dashboard row density")
                        }
                        settingsControlRow("Default history range") {
                            Picker("Default history range", selection: defaultHistoryRangeBinding) {
                                ForEach(HistoryRange.uiSelectable, id: \.rawValue) { range in
                                    Text(range.displayName).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel("Default history range")
                        }
                        Text("Used for inline charts and the history popover unless a value has its own range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("Show updated timestamp in the footer", isOn: footerTimestampBinding)
                            .fixedSize()
                            .accessibilityLabel("Show the dashboard footer updated timestamp")
                    }
                }
            }
            settingsCard {
                settingsSection(title: "Reset", systemImage: "arrow.counterclockwise") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Restore the display preferences (menu-bar appearance, theme, and accent) to their defaults. Your connection and entities are not changed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            updateDisplayPreferences(.defaults)
                        } label: {
                            Label("Reset display preferences", systemImage: "arrow.counterclockwise")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(PerchHAIconButtonStyle())
                        .disabled(displayPreferences == .defaults)
                        .help("Reset menu-bar appearance, theme, and accent to defaults")
                        .accessibilityLabel("Reset display preferences to defaults")
                    }
                }
            }
        }
    }

    /// A sample dashboard telemetry row rendered on the dashboard surface using
    /// the currently-chosen accent and density, so the Appearance preview shows
    /// both a menu-bar item (from ``PerchHAAppearancePreview``) and a real
    /// dashboard row reflecting the live theme/accent.
    private var appearanceDashboardSample: some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let accent = color(for: displayPreferences.accentColor)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard row")
                .font(PerchHATypography.caption())
                .foregroundStyle(palette.textTertiary)
            TelemetryRow(
                icon: "thermometer.medium",
                iconActive: true,
                label: "Living room",
                subtitle: "Temperature",
                preview: {
                    MicroMeter(fraction: 0.62, color: accent, trackColor: palette.meterTrack)
                        .frame(width: 54, height: 6)
                },
                value: {
                    Text("21.4°")
                        .font(PerchHATypography.bodyValue())
                        .foregroundStyle(palette.textPrimary)
                },
                control: { EmptyView() }
            )
            .background(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(palette.surfaceRoot)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .strokeBorder(palette.borderSubtle, lineWidth: 1)
            )
            .environment(\.dashboardPalette, palette)
            .environment(\.dashboardRowDensity, displayPreferences.dashboardRowDensity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sample dashboard row, Living room temperature 21.4 degrees")
        }
    }

    private var themeModePicker: some View {
        Picker("Theme", selection: themeModeBinding) {
            ForEach(PerchHAThemeMode.allCases, id: \.rawValue) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Theme")
    }

    private var accentMenuPicker: some View {
        Picker("Accent", selection: accentSwatchBinding) {
            ForEach(PerchHAAccentColor.swatches) { swatch in
                Text(swatch.name).tag(swatch.id)
            }
        }
        .labelsHidden()
        .frame(width: 160)
        .perchHACompactControl()
        .accessibilityLabel("Accent color")
    }

    private var accentSwatchPreview: some View {
        HStack(spacing: 8) {
            ForEach(PerchHAAccentColor.swatches) { swatch in
                let isSelected = displayPreferences.accentColor == swatch.color
                Button {
                    updateDisplayPreferences(displayPreferences.with(accentColor: swatch.color))
                } label: {
                    Circle()
                        .fill(color(for: swatch.color))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().strokeBorder(
                                isSelected ? Color.primary.opacity(0.75) : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 2 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .help(swatch.name)
                .accessibilityLabel(swatch.name)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(for accent: PerchHAAccentColor) -> Color {
        Color(.sRGB, red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.alpha)
    }

    // MARK: Diagnostics

    /// Diagnostics: real connection status, entity health (the warning count and
    /// a deduped, capped list of affected entities), the last-updated timestamp
    /// with a manual refresh action, and the read-only history-prefetch
    /// reference. All values come from the live snapshot; nothing is fabricated.
    /// This is the only place a manual refresh lives.
    private var diagnosticsTab: some View {
        let health = entityHealth
        return settingsPage(title: "Diagnostics", systemImage: Tab.diagnostics.systemImage) {
            settingsCard {
                settingsSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    diagnosticsConnectionContent
                }
            }
            settingsCard {
                settingsSection(title: "Retry & backoff", systemImage: "arrow.triangle.2.circlepath") {
                    diagnosticsRetryContent
                }
            }
            settingsCard {
                settingsSection(title: "Recent issues", systemImage: "list.bullet.rectangle") {
                    diagnosticsRecentIssuesContent
                }
            }
            settingsCard {
                settingsSection(title: "Entity health", systemImage: "heart.text.square") {
                    diagnosticsHealthContent(health)
                }
            }
            settingsCard {
                settingsSection(title: "Updates", systemImage: "clock.arrow.circlepath") {
                    diagnosticsUpdatesContent
                }
            }
            settingsCard {
                settingsSection(title: "History sync", systemImage: "chart.line.uptrend.xyaxis") {
                    diagnosticsHistorySyncContent
                }
            }
        }
    }

    /// The connection diagnostic: a status pill carrying its own text plus the
    /// last error message when the snapshot reports one.
    private var diagnosticsConnectionContent: some View {
        let status = connectionDiagnostic
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusPill(
                    status.label,
                    systemImage: status.systemImage,
                    color: status.color,
                    accessibilityLabel: "Connection \(status.label)"
                )
                Spacer(minLength: 0)
            }
            if let detail = model.snapshot.failureDescription {
                PerchHAErrorState(
                    title: "Last error",
                    message: detail,
                    style: .inline,
                    accessibilityPrefix: "Connection error"
                )
            } else {
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The retry/backoff diagnostic: a single calm line derived from the live
    /// connection state and the periodic-refresh backoff posture. No secret.
    private var diagnosticsRetryContent: some View {
        let state = model.retryBackoffState
        let isHealthy: Bool = {
            switch state {
            case .connected: return true
            case .connecting, .reconnecting, .backingOff, .disconnected: return false
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusPill(
                    state.summary,
                    systemImage: isHealthy ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath",
                    color: isHealthy ? PerchHATheme.ok : PerchHATheme.warn,
                    accessibilityLabel: "Retry state: \(state.summary)"
                )
                Spacer(minLength: 0)
            }
            Text("Background refresh backs off automatically after repeated failures and resumes once the connection recovers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The recent-issues diagnostic: the deduped diagnostic ring buffer, newest
    /// first, capped to a sensible visible number with the remainder summarized,
    /// plus a "Clear diagnostics" action. A calm empty state when nothing is
    /// recorded. Messages come straight from the sanitized event log; no secret
    /// is ever shown.
    @ViewBuilder
    private var diagnosticsRecentIssuesContent: some View {
        let events = model.diagnosticEvents
        let visibleCap = 8
        if events.isEmpty {
            PerchHAStateView(
                systemImage: "checkmark.seal",
                symbolTint: PerchHATheme.ok,
                title: "No recent issues",
                message: "Connection problems, reconnects, and recoveries will appear here.",
                emphasis: .inline
            )
        } else {
            let visible = Array(events.prefix(visibleCap))
            let hidden = events.count - visible.count
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, event in
                        diagnosticEventRow(event)
                        if index < visible.count - 1 {
                            Divider().accessibilityHidden(true)
                        }
                    }
                }
                if hidden > 0 {
                    Text("and \(hidden) more \(hidden == 1 ? "event" : "events")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        model.clearDiagnostics()
                    } label: {
                        Label("Clear diagnostics", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .help("Remove all recorded diagnostic events")
                    .accessibilityLabel("Clear diagnostics")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A single recorded diagnostic event row: kind icon + message + relative age,
    /// with a "×N" badge when the event was deduplicated more than once.
    private func diagnosticEventRow(_ event: PerchHADiagnosticEvent) -> some View {
        let tint: Color = {
            switch event.kind {
            case .recovered: return PerchHATheme.ok
            case .reconnecting, .liveUpdatesInterrupted: return PerchHATheme.warn
            case .connectionFailed, .refreshFailed: return PerchHATheme.critical
            }
        }()
        let countSuffix = event.count > 1 ? " ×\(event.count)" : ""
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: event.kind.systemImage)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(event.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if event.count > 1 {
                Text("×\(event.count)")
                    .font(PerchHATypography.caption().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(model.relativeAgeDescription(for: event))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.message)\(countSuffix), \(model.relativeAgeDescription(for: event))")
    }

    /// The entity-health diagnostic: the warning count and a deduped, capped
    /// summary of affected entities, or a calm "all healthy" / "no values" state.
    @ViewBuilder
    private func diagnosticsHealthContent(_ health: EntityHealthReport) -> some View {
        if health.totalVisible == 0 {
            PerchHAStateView(
                systemImage: "tray",
                title: "No values yet",
                message: "Connect and select some values to see their health here.",
                emphasis: .inline
            )
        } else if health.warningCount == 0 {
            PerchHAStateView(
                systemImage: "checkmark.seal",
                symbolTint: PerchHATheme.ok,
                title: "All values healthy",
                message: "\(health.totalVisible) visible \(health.totalVisible == 1 ? "value is" : "values are") reporting normally.",
                emphasis: .inline
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusPill(
                        health.warningCount == 1 ? "1 needs attention" : "\(health.warningCount) need attention",
                        systemImage: "exclamationmark.triangle.fill",
                        color: PerchHATheme.warn,
                        accessibilityLabel: "\(health.warningCount) of \(health.totalVisible) values need attention"
                    )
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    ForEach(Array(health.visibleGroups.enumerated()), id: \.offset) { index, group in
                        HStack(spacing: 8) {
                            Image(systemName: group.systemImage)
                                .font(.caption)
                                .foregroundStyle(PerchHATheme.warn)
                                .frame(width: 18)
                                .accessibilityHidden(true)
                            Text(group.label)
                                .font(.callout)
                            Spacer(minLength: 8)
                            Text("\(group.count)")
                                .font(PerchHATypography.bodyValue())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(group.label), \(group.count)")
                        if index < health.visibleGroups.count - 1 {
                            Divider().accessibilityHidden(true)
                        }
                    }
                }
                if health.hiddenCount > 0 {
                    Text("and \(health.hiddenCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The updates diagnostic: the last-updated description plus a manual
    /// "Refresh now" action. Refresh is otherwise automatic (on open,
    /// periodically while open, and via live WebSocket push).
    private var diagnosticsUpdatesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingsControlRow("Last updated") {
                Text(model.snapshot.lastUpdateDescription)
                    .font(PerchHATypography.bodyValue())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Values update live while the panel is open and refresh automatically in the background.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.startRefresh()
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .disabled(model.snapshot.connectionState != .connected)
            .help("Fetch the latest values from Home Assistant now")
            .accessibilityLabel("Refresh values now")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsHistorySyncContent: some View {
        let sync = PerchHAHistoryBulkSyncConfiguration()
        return VStack(alignment: .leading, spacing: 6) {
            settingsControlRow("Cycle interval") {
                Text("\(sync.interval.nanoseconds / 1_000_000_000) s")
                    .foregroundStyle(.secondary)
            }
            settingsControlRow("Settle delay") {
                Text("\(sync.settleDelay.nanoseconds / 1_000_000) ms")
                    .foregroundStyle(.secondary)
            }
            settingsControlRow("Batch size") {
                Text("\(sync.batchSize) values per request")
                    .foregroundStyle(.secondary)
            }
            Text("While the panel is open, inline charts refresh in bulk on this cadence — visible rows every cycle, the rest periodically. These are tuned defaults shown for reference.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A resolved connection status for the Diagnostics pill, mapped from the
    /// real snapshot connection state.
    private var connectionDiagnostic: (label: String, detail: String, systemImage: String, color: Color) {
        switch model.snapshot.connectionState {
        case .connected:
            return ("Connected", "Live updates are flowing from Home Assistant.", "checkmark.circle.fill", PerchHATheme.ok)
        case .connecting:
            return ("Connecting", "Establishing a connection to Home Assistant.", "hourglass", PerchHATheme.warn)
        case let .reconnecting(attempt):
            return ("Reconnecting", "Attempt \(attempt). Showing the last known values.", "arrow.triangle.2.circlepath", PerchHATheme.warn)
        case .disconnected:
            return ("Disconnected", "Not connected to Home Assistant.", "bolt.horizontal.circle", .secondary)
        case let .failed(failure):
            switch failure {
            case .authentication:
                return ("Permission", "Sign in again or check your access token.", "lock.circle.fill", PerchHATheme.critical)
            case .unreachable, .tlsRejected, .unsupportedCommand, .protocolError:
                return ("Error", "Connection failed. See the last error below.", "exclamationmark.circle.fill", PerchHATheme.critical)
            }
        }
    }

    /// A deduped, capped report of unhealthy entities, built from the same
    /// visible rooms the dashboard warning count uses. Identical statuses are
    /// grouped with a count; the visible list is capped so a large fleet does not
    /// dump hundreds of rows.
    private var entityHealth: EntityHealthReport {
        let visible = model.snapshot.rooms.flatMap(\.entities)
        var unavailable = 0
        var unknown = 0
        var stale = 0
        for entity in visible {
            switch model.snapshot.formattedValue(for: entity).status {
            case .unavailable: unavailable += 1
            case .unknown: unknown += 1
            case .stale: stale += 1
            case .available: break
            }
        }
        let groups: [EntityHealthGroup] = [
            EntityHealthGroup(label: "Unavailable", count: unavailable, systemImage: "wifi.slash"),
            EntityHealthGroup(label: "Unknown", count: unknown, systemImage: "questionmark.circle"),
            EntityHealthGroup(label: "Stale", count: stale, systemImage: "clock.badge.exclamationmark")
        ].filter { $0.count > 0 }
        let cap = 3
        return EntityHealthReport(
            totalVisible: visible.count,
            warningCount: unavailable + unknown + stale,
            visibleGroups: Array(groups.prefix(cap)),
            hiddenCount: groups.dropFirst(cap).reduce(0) { $0 + $1.count }
        )
    }

    // MARK: Privacy

    /// Privacy statement: a static, honest summary of what PearchHA reads, where
    /// credentials live, and the absence of analytics or third-party calls.
    private var privacyTab: some View {
        settingsPage(title: "Privacy", systemImage: Tab.privacy.systemImage) {
            settingsCard {
                settingsSection(title: "What PearchHA reads", systemImage: "doc.text.magnifyingglass") {
                    Text("PearchHA talks only to the Home Assistant server you configure. It reads your Home Assistant address and the access token (or browser sign-in) you provide, plus the entity states needed to show your values.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSectionDivider
                settingsSection(title: "Where credentials live", systemImage: "key") {
                    Text("Your access and refresh tokens are stored in the macOS Keychain on this Mac. They are never written to the configuration file and never shown in this window.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsSectionDivider
                settingsSection(title: "No tracking", systemImage: "hand.raised") {
                    Text("PearchHA makes no analytics, telemetry, or third-party network calls. Nothing is sent anywhere except your own Home Assistant server.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: General bindings

    private func updateDisplayPreferences(_ preferences: PerchHADisplayPreferences) {
        displayPreferences = preferences
        displayPreferencesSink(preferences)
    }

    private var stableMenuBarWidthBinding: Binding<Bool> {
        Binding(
            get: { displayPreferences.stableMenuBarWidth },
            set: { updateDisplayPreferences(displayPreferences.with(stableMenuBarWidth: $0)) }
        )
    }

    private var menuBarAppearanceBinding: Binding<PerchHAMenuBarAppearance> {
        Binding(
            get: { displayPreferences.menuBarAppearance },
            set: { updateDisplayPreferences(displayPreferences.with(menuBarAppearance: $0)) }
        )
    }

    private var rowDensityBinding: Binding<PerchHADashboardRowDensity> {
        Binding(
            get: { displayPreferences.dashboardRowDensity },
            set: { updateDisplayPreferences(displayPreferences.with(dashboardRowDensity: $0)) }
        )
    }

    private var defaultHistoryRangeBinding: Binding<HistoryRange> {
        Binding(
            get: { displayPreferences.defaultHistoryRange },
            set: { updateDisplayPreferences(displayPreferences.with(defaultHistoryRange: $0)) }
        )
    }

    private var footerTimestampBinding: Binding<Bool> {
        Binding(
            get: { displayPreferences.showsFooterTimestamp },
            set: { updateDisplayPreferences(displayPreferences.with(showsFooterTimestamp: $0)) }
        )
    }

    private func entityIconVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: { model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsEntityIcon },
            set: { model.setShowsEntityIcon(id, showsEntityIcon: $0) }
        )
    }

    private var themeModeBinding: Binding<PerchHAThemeMode> {
        Binding(
            get: { displayPreferences.themeMode },
            set: { updateDisplayPreferences(displayPreferences.with(themeMode: $0)) }
        )
    }

    private var accentSwatchBinding: Binding<String> {
        Binding(
            get: { displayPreferences.accentColor.matchingSwatchID ?? PerchHAAccentColor.swatches.first?.id ?? "ha-blue" },
            set: { id in
                guard let swatch = PerchHAAccentColor.swatches.first(where: { $0.id == id }) else {
                    return
                }
                updateDisplayPreferences(displayPreferences.with(accentColor: swatch.color))
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { requested in
                // Reflect the real resulting login-item state: if the service
                // call fails, the toggle snaps back instead of lying.
                let applied = launchAtLoginSink(requested)
                launchAtLogin = applied ? requested : launchAtLoginProvider()
                // Surface a calm permission message only when the user asked to
                // enable launch at login and the system declined.
                launchAtLoginPermissionDenied = requested && !applied
            }
        )
    }

    private var aboutTab: some View {
        settingsPage(title: "About", systemImage: Tab.about.systemImage) {
            aboutIdentityCard
            aboutDetailsCard
            aboutSupportCard
        }
    }

    /// Identity card: the real application icon, the app name, version, and a
    /// one-line description of what PearchHA is.
    private var aboutIdentityCard: some View {
        settingsCard {
            HStack(alignment: .center, spacing: 14) {
                aboutAppIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text("PearchHA")
                        .font(.title2.weight(.semibold))
                    Text("Version \(Self.applicationVersion)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("PearchHA, version \(Self.applicationVersion)")
            Text("A calm Home Assistant menu-bar companion for macOS.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The real application icon at a tasteful size, falling back to an SF Symbol
    /// glyph when no app icon is available (for example in non-bundle render
    /// paths).
    @ViewBuilder
    private var aboutAppIcon: some View {
        if let icon = Self.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 68, height: 68)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "house.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(PerchHATheme.accent)
                .accessibilityHidden(true)
        }
    }

    /// Details card: license, developer, and repository, with the license and
    /// repository as browser links.
    private var aboutDetailsCard: some View {
        settingsCard {
            settingsSection(title: "Details", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    settingsControlRow("License") {
                        Link("MIT License", destination: Self.licenseURL)
                            .accessibilityLabel("MIT License, opens in browser")
                    }
                    settingsControlRow("Developer") {
                        Text("YunaBraska")
                            .foregroundStyle(.secondary)
                    }
                    settingsControlRow("Repository") {
                        Link("github.com/YunaBraska/pearch_ha", destination: Self.repositoryURL)
                            .accessibilityLabel("Repository on GitHub, opens in browser")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    /// Support card: optional appreciation links (repo star, sponsor/coffee/Ko-fi/
    /// Liberapay) plus an issues/feedback link.
    private var aboutSupportCard: some View {
        settingsCard {
            settingsSection(title: "Support", systemImage: "heart") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("If it earned a place on your menu bar, a star on the repo helps. If you want to fuel a coffee:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        aboutSupportLink("GitHub Sponsors", systemImage: "heart.fill", destination: Self.sponsorsURL)
                        aboutSupportLink("Buy Me a Coffee", systemImage: "cup.and.saucer.fill", destination: Self.buyMeACoffeeURL)
                    }
                    HStack(spacing: 8) {
                        aboutSupportLink("Ko-fi", systemImage: "mug.fill", destination: Self.koFiURL)
                        aboutSupportLink("Liberapay", systemImage: "banknote", destination: Self.liberapayURL)
                    }
                    Link(destination: Self.issuesURL) {
                        Label("Issues / feedback", systemImage: "exclamationmark.bubble")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PerchHAIconButtonStyle())
                    .accessibilityLabel("Issues and feedback on GitHub, opens in browser")
                }
            }
        }
    }

    /// A single design-system styled support link with an SF Symbol and an
    /// accessible name describing where it leads.
    private func aboutSupportLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
        .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
        .accessibilityLabel("\(title), opens in browser")
    }

    private static let repositoryURL = URL(string: "https://github.com/YunaBraska/pearch_ha")!
    private static let licenseURL = URL(string: "https://github.com/YunaBraska/pearch_ha/blob/main/LICENSE")!
    private static let issuesURL = URL(string: "https://github.com/YunaBraska/pearch_ha/issues")!
    private static let sponsorsURL = URL(string: "https://github.com/sponsors/YunaBraska")!
    private static let buyMeACoffeeURL = URL(string: "https://buymeacoffee.com/YunaBraska")!
    private static let koFiURL = URL(string: "https://ko-fi.com/YunaBraska")!
    private static let liberapayURL = URL(string: "https://liberapay.com/YunaBraska")!

    /// The running application's icon, used in the About identity card. Resolves
    /// from the live `NSApp` icon first, then the named application icon.
    private static var applicationIconImage: NSImage? {
        NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
    }

    private static let applicationVersion: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (short?, build?):
            return "\(short) (\(build))"
        case let (short?, nil):
            return short
        case let (nil, build?):
            return build
        case (nil, nil):
            return "1.0"
        }
    }()

    private var entitiesTab: some View {
        settingsPage(title: "Entities", systemImage: Tab.entities.systemImage) {
            settingsContent
        }
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PerchHACapsuleField(systemImage: "magnifyingglass") {
                    TextField("Search", text: selectionSearchBinding)
                        .textFieldStyle(.plain)
                }
                Button {
                    model.setAllEntities(isSelected: true)
                } label: {
                    Label("Select all", systemImage: "checkmark.circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PerchHAIconButtonStyle())
                .help("Show every discovered value in the panel")
                .accessibilityLabel("Select all")
                Button {
                    model.setAllEntities(isSelected: false)
                } label: {
                    Label("Clear", systemImage: "circle")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PerchHAIconButtonStyle())
                .help("Hide every value from the panel")
                .accessibilityLabel("Clear")
                collapseAllControl
            }
            .disabled(model.snapshot.availableRooms.isEmpty)
            if let selectionPersistenceFailure = model.snapshot.selectionPersistenceFailureDescription {
                Text(selectionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Selection settings error: \(selectionPersistenceFailure)")
            }
            if let displayPersistenceFailure = model.snapshot.displayPersistenceFailureDescription {
                Text(displayPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Display settings error: \(displayPersistenceFailure)")
            }
            if let serviceMetadataFailure = model.snapshot.serviceMetadataFailureDescription {
                Text(serviceMetadataFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Service metadata error: \(serviceMetadataFailure)")
            }
            if let customActionPersistenceFailure = model.customActionPersistenceFailureDescription {
                Text(customActionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Action settings error: \(customActionPersistenceFailure)")
            }
            if let shellPersistenceFailure = model.shellPersistenceFailureDescription {
                Text(shellPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Storage error: \(shellPersistenceFailure)")
            }
            if !model.orphanedCustomActions.isEmpty {
                orphanedCustomActionControls
            }
            if settingsTree.isEmpty {
                Text("No matching values.")
                    .foregroundStyle(.secondary)
            } else {
                let tree = settingsTree
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tree.enumerated()), id: \.element.id.rawValue) { index, room in
                        selectionRoom(
                            room,
                            canMoveUp: canReorderSelection && index > tree.startIndex,
                            canMoveDown: canReorderSelection && index < tree.index(before: tree.endIndex)
                        )
                    }
                }
            }
        }
    }

    private var orphanedCustomActionControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unused buttons")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.orphanedCustomActions, id: \.id.rawValue) { action in
                HStack(spacing: 6) {
                    Text("\(action.title) - \(action.entityID.rawValue)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removeCustomAction(action.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PerchHACircularIconButtonStyle())
                    .controlSize(.small)
                    .help("Delete unused button")
                    .accessibilityLabel("Delete unused button \(action.title)")
                }
            }
        }
    }

    private var settingsTree: [SelectableRoom] {
        model.settingsSelectionTree
    }

    private var canReorderSelection: Bool {
        model.snapshot.canReorderSelectionWithKeyboard
    }

    /// True while the user is filtering the entity tree. During a search every
    /// rendered room is forced expanded so matches are never hidden behind a
    /// collapsed header; the stored ``collapsedRooms`` set is left untouched so
    /// clearing the search restores the prior state.
    private var isSelectionSearching: Bool {
        !model.snapshot.selectionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether `room` should show its entity rows. A room is expanded unless it
    /// is in ``collapsedRooms``; an active search or the room holding the open
    /// inspector forces it expanded without mutating the stored state.
    private func isRoomExpanded(_ room: SelectableRoom) -> Bool {
        let containsInspected = inspectedEntityID.map { id in
            room.entities.contains { $0.entity.id == id }
        } ?? false
        return SelectionRoomCollapse.isExpanded(
            roomID: room.id.rawValue,
            collapsedRoomIDs: collapsedRooms,
            isSearching: isSelectionSearching,
            roomContainsInspectedEntity: containsInspected
        )
    }

    /// True when every currently-shown room is collapsed, used to flip the
    /// collapse-all affordance to "Expand all". Searching counts as expanded.
    private var allRoomsCollapsed: Bool {
        SelectionRoomCollapse.allCollapsed(
            roomIDs: settingsTree.map { $0.id.rawValue },
            collapsedRoomIDs: collapsedRooms,
            isSearching: isSelectionSearching
        )
    }

    /// A small token-styled control that collapses or expands every room at once.
    /// While searching it is disabled, since search already forces rooms open.
    private var collapseAllControl: some View {
        let expandAll = allRoomsCollapsed
        return Button {
            withSelectionAnimation {
                if expandAll {
                    collapsedRooms.removeAll()
                } else {
                    collapsedRooms = Set(settingsTree.map { $0.id.rawValue })
                }
            }
        } label: {
            Label(
                expandAll ? "Expand all" : "Collapse all",
                systemImage: expandAll ? "chevron.down.square" : "chevron.up.square"
            )
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(PerchHAIconButtonStyle())
        .disabled(isSelectionSearching || settingsTree.isEmpty)
        .help(expandAll ? "Show every room's values" : "Hide every room's values")
        .accessibilityLabel(expandAll ? "Expand all rooms" : "Collapse all rooms")
    }

    /// Toggles `room`'s collapsed state. Collapsing the room that holds the open
    /// inspector also closes the inspector, so the inspected entity is never left
    /// stranded behind a collapsed header.
    private func toggleRoomCollapsed(_ room: SelectableRoom) {
        let id = room.id.rawValue
        withSelectionAnimation {
            if collapsedRooms.contains(id) {
                collapsedRooms.remove(id)
            } else {
                collapsedRooms.insert(id)
                if let inspectedEntityID, room.entities.contains(where: { $0.entity.id == inspectedEntityID }) {
                    self.inspectedEntityID = nil
                }
            }
        }
    }

    /// Runs `body` inside a calm expand/collapse animation, or with no animation
    /// when the resolved accessibility preference asks for reduced motion.
    private func withSelectionAnimation(_ body: () -> Void) {
        let reduceMotion = accessibilityPreferences.motionPolicy == .reduced
        if let animation = PerchHAMotion.animation(reduceMotion: reduceMotion) {
            withAnimation(animation, body)
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, body)
        }
    }

    private func selectionRoom(_ room: SelectableRoom, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        let isExpanded = isRoomExpanded(room)
        return VStack(alignment: .leading, spacing: 5) {
            selectionDragDrop(
                selectionRoomHeader(
                    room,
                    isExpanded: isExpanded,
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
                .padding(.horizontal, PerchHASpacing.xs),
                item: .room(room.id)
            )
            if isExpanded {
                entitiesRoomCard(room)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// A tappable room header that reads as a section header (uppercase room name
    /// + entity count) and toggles the room's collapsed state. A leading chevron
    /// rotates to communicate expanded/collapsed; the per-room reorder controls
    /// stay in the trailing slot. The toggle is a `Button`, so it is keyboard
    /// activatable and carries an expanded/collapsed accessibility value.
    private func selectionRoomHeader(
        _ room: SelectableRoom,
        isExpanded: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let count = room.entities.count
        let countLabel = count == 1 ? "1 entity" : "\(count) entities"
        return HStack(spacing: PerchHASpacing.xs + 1) {
            Button {
                toggleRoomCollapsed(room)
            } label: {
                HStack(spacing: PerchHASpacing.xs + 1) {
                    Image(systemName: "chevron.right")
                        .font(PerchHATypography.caption())
                        .foregroundStyle(palette.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(room.name)
                        .font(PerchHATypography.caption())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .lineLimit(1)
                    Text("· \(count)")
                        .font(PerchHATypography.caption())
                        .foregroundStyle(palette.textTertiary)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSelectionSearching)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(room.name), \(countLabel)")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Collapse room" : "Expand room")
            .accessibilityAddTraits(.isButton)
            selectionMoveButtons(
                up: {
                    model.moveRoom(room.id, direction: .up)
                },
                down: {
                    model.moveRoom(room.id, direction: .down)
                },
                upLabel: "Move \(room.name) up",
                downLabel: "Move \(room.name) down",
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown
            )
        }
    }

    /// A token-styled card holding the collapsed entity rows for one room,
    /// matching the dashboard panel surface with hairline separators between
    /// rows.
    private func entitiesRoomCard(_ room: SelectableRoom) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        // Lazy rows: an expanded room with hundreds of entities materializes
        // only what scrolls into view instead of building every row up front.
        return LazyVStack(spacing: 0) {
            ForEach(Array(room.entities.enumerated()), id: \.element.entity.id.rawValue) { index, selectable in
                selectionDragDrop(
                    selectionEntityRow(
                        selectable,
                        canMoveUp: canReorderSelection && index > room.entities.startIndex,
                        canMoveDown: canReorderSelection && index < room.entities.index(before: room.entities.endIndex)
                    ),
                    item: .entity(selectable.entity.id)
                )
                if index < room.entities.count - 1 {
                    Rectangle()
                        .fill(palette.separatorSubtle)
                        .frame(height: 1)
                        .padding(.leading, 34)
                }
            }
        }
        .padding(.vertical, PerchHASpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .fill(palette.surfacePanel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchHACornerRadius.card, style: .continuous)
                .strokeBorder(palette.borderSubtle, lineWidth: 1)
        )
    }

    /// A compact, collapsed entity row: selection checkbox, domain icon, name,
    /// a type/unit caption, a menu-bar-visible pill, reorder controls, and a
    /// disclosure toggle that opens this entity's inspector. Clicking the row
    /// (or the disclosure) opens the single inspector inline beneath the row;
    /// only one inspector is open at a time.
    private func selectionEntityRow(
        _ selectable: SelectableEntity,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let palette = PerchHATheme.Dashboard.palette(colorScheme)
        let entity = selectable.entity
        let isExpanded = inspectedEntityID == entity.id
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: selectionBinding(for: entity.id))
                    .labelsHidden()
                    .accessibilityLabel("Show \(entity.name) in panel")
                Image(systemName: perchHAEntityIconName(for: entity))
                    .font(.system(size: 14))
                    .frame(width: 22, alignment: .center)
                    .foregroundStyle(isExpanded ? palette.accentPrimary : palette.textSecondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(entity.name)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(entityTypeCaption(for: entity))
                        .font(PerchHATypography.caption().weight(.regular))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if isPromoted {
                    menuBarVisiblePill
                }
                selectionMoveButtons(
                    up: {
                        model.moveEntity(entity.id, direction: .up)
                    },
                    down: {
                        model.moveEntity(entity.id, direction: .down)
                    },
                    upLabel: "Move \(entity.name) up",
                    downLabel: "Move \(entity.name) down",
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
                Button {
                    toggleEntityInspector(entity.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PerchHACircularIconButtonStyle())
                .controlSize(.small)
                .help(isExpanded ? "Hide settings" : "Show settings")
                .accessibilityLabel(isExpanded ? "Hide \(entity.name) settings" : "Show \(entity.name) settings")
            }
            .font(.body)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleEntityInspector(entity.id)
            }
            if isExpanded {
                settingsInsetGroup {
                    entityDetailSections(for: entity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isExpanded
                ? RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(palette.accentPrimary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                : nil
        )
    }

    /// The compact "shown in menu bar" pill used on a collapsed entity row.
    private var menuBarVisiblePill: some View {
        StatusPill(
            "Menu bar",
            systemImage: "menubar.rectangle",
            color: PerchHATheme.Dashboard.palette(colorScheme).accentPrimary,
            accessibilityLabel: "Shown in menu bar"
        )
    }

    /// A short type/unit caption for a collapsed entity row, e.g. "Sensor · °C".
    private func entityTypeCaption(for entity: DiscoveredEntity) -> String {
        let domain = entity.id.domain.replacingOccurrences(of: "_", with: " ").capitalized
        let unit = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let unit, !unit.isEmpty {
            return "\(domain) · \(unit)"
        }
        return domain
    }

    /// Opens the inspector for `id`, collapsing any other open inspector so only
    /// one is ever open; tapping the open row collapses it.
    private func toggleEntityInspector(_ id: EntityID) {
        inspectedEntityID = (inspectedEntityID == id) ? nil : id
    }

    /// The bespoke detail pane shown when an entity row is expanded: clearly
    /// labelled Display, Menu bar, Alerts, and Buttons sections with
    /// accent-tinted headers and accent-tinted controls, separated by hairlines.
    private func entityDetailSections(for entity: DiscoveredEntity) -> some View {
        let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 0) {
            settingsSection(title: "Display", systemImage: "textformat.size") {
                displaySectionControls(for: entity, configuration: configuration, isPromoted: isPromoted)
            }
            settingsSectionDivider
            settingsSection(title: "Menu bar", systemImage: "menubar.rectangle") {
                menuBarSectionControls(for: entity, isPromoted: isPromoted)
            }
            if isPromoted {
                settingsSectionDivider
                settingsSection(title: "Thresholds", systemImage: "bell.badge") {
                    menuBarThresholdControls(for: entity, configuration: configuration)
                }
            }
        }
        .font(.caption)
        .controlSize(.small)
        .tint(PerchHATheme.accent)
    }

    /// A single labelled settings section with a small accent-tinted leading SF
    /// Symbol header and right-aligned controls in the bespoke PerchHA language.
    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: PerchHASpacing.sm) {
            PerchHASectionHeader(title, systemImage: systemImage)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, PerchHASpacing.sm)
    }

    private var settingsSectionDivider: some View {
        Divider()
            .accessibilityHidden(true)
    }

    /// Display section: how the value is rendered (style, unit, min/max,
    /// label/unit toggles, decimals). Excludes promotion/reorder and alerts.
    @ViewBuilder
    private func displaySectionControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        isPromoted: Bool
    ) -> some View {
        let isNumeric = menuBarNumericState(entity.state) != nil
        let isCover = entity.id.domain == "cover"
        VStack(alignment: .leading, spacing: 6) {
            if isNumeric {
                settingsControlRow("Style") {
                    Picker("Style", selection: menuBarStyleBinding(for: entity.id)) {
                        ForEach(MenuBarDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) display style")
                }
            }

            if isCover {
                settingsControlRow("Controls") {
                    Picker("Controls", selection: coverControlModeBinding(for: entity.id)) {
                        ForEach(CoverControlMode.allCases, id: \.rawValue) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) cover controls")
                }
            }

            unitDisplayControls(for: entity, configuration: configuration)

            settingsControlRow("Icon") {
                entityIconPicker(for: entity, configuration: configuration)
            }

            settingsControlRow("Chart range") {
                Picker("Chart range", selection: menuBarHistoryRangeBinding(for: entity.id)) {
                    Text("Auto").tag(HistoryRange?.none)
                    ForEach(HistoryRange.allCases, id: \.rawValue) { range in
                        Text(range.displayName).tag(HistoryRange?.some(range))
                    }
                }
                .labelsHidden()
                .frame(width: 96)
                .accessibilityLabel("\(entity.name) chart range")
            }

            if isPromoted {
                settingsControlRow("Decimals") {
                    Picker("Decimals", selection: menuBarDecimalsBinding(for: entity.id)) {
                        ForEach(0...3, id: \.self) { digits in
                            Text("\(digits)").tag(digits)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("\(entity.name) decimals")
                }
                if configuration.style != .text && menuBarCanUseGaugeTotal(for: entity) {
                    menuBarTotalControls(for: entity, configuration: configuration)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The entity's icon picker: the custom SF Symbol used everywhere this
    /// value appears (dashboard row and menu bar), or Automatic for the
    /// domain-derived symbol.
    private func entityIconPicker(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        Menu {
            Button {
                model.setCustomEntityIcon(entity.id, symbolName: nil)
            } label: {
                Label("Automatic", systemImage: perchHAEntityIconName(for: entity))
            }
            ForEach(PerchHAEntityIconCatalog.sections, id: \.title) { section in
                Section(section.title) {
                    ForEach(section.symbols, id: \.self) { symbol in
                        Button {
                            model.setCustomEntityIcon(entity.id, symbolName: symbol)
                        } label: {
                            Label(symbol, systemImage: symbol)
                        }
                    }
                }
            }
        } label: {
            Label(
                configuration.customIconName ?? "Automatic",
                systemImage: configuration.customIconName ?? perchHAEntityIconName(for: entity)
            )
        }
        .fixedSize()
        .accessibilityLabel("\(entity.name) icon, currently \(configuration.customIconName ?? "automatic")")
    }

    /// Menu bar section: whether the entity is shown in the menu bar and its
    /// position there.
    private func menuBarSectionControls(for entity: DiscoveredEntity, isPromoted: Bool) -> some View {
        let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Show in menu bar", isOn: menuBarVisibilityBinding(for: entity.id))
                    .fixedSize()
                    .accessibilityLabel("Show \(entity.name) in menu bar")
                if isPromoted {
                    menuBarMoveButtons(for: entity)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPromoted {
                HStack(spacing: 12) {
                    Toggle("Show icon", isOn: entityIconVisibilityBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) icon in the menu bar")
                    Toggle("Show label", isOn: menuBarLabelBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) label in menu bar")
                    Toggle("Show unit", isOn: menuBarUnitBinding(for: entity.id))
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) unit in menu bar")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A label-column row with right-aligned trailing controls, used for the
    /// aligned settings layout.
    private func settingsControlRow<Trailing: View>(
        _ label: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func unitDisplayControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let detected = EntityDisplayDefaults.detectedUnit(haUnit: entity.unit, state: entity.state)
        let effectiveUnit = configuration.displayUnit ?? detected
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Unit")
                    .foregroundStyle(.secondary)
                Picker("Unit", selection: displayUnitBinding(for: entity.id)) {
                    Text("Detected · \(detected.displayName)").tag(ValueUnit?.none)
                    ForEach(ValueUnit.allCases, id: \.rawValue) { unit in
                        Text(unit.displayName).tag(ValueUnit?.some(unit))
                    }
                }
                .labelsHidden()
                .frame(width: 160)
                .accessibilityLabel("\(entity.name) unit")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if effectiveUnit.usesNormalizedFraction {
                HStack(spacing: 8) {
                    Text("Min")
                        .foregroundStyle(.secondary)
                    TextField("0", text: displayMinBinding(for: entity.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(entity.name) minimum value")
                    Text("Max")
                        .foregroundStyle(.secondary)
                    TextField("100", text: displayMaxBinding(for: entity.id))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .accessibilityLabel("\(entity.name) maximum value")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func menuBarTotalControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let candidates = menuBarTotalCandidates(for: entity)
        return HStack(spacing: 8) {
            Picker("Total", selection: menuBarTotalModeBinding(for: entity.id)) {
                Text("No total").tag(MenuBarTotalMode.none)
                Text("Manual").tag(MenuBarTotalMode.absolute)
                if let totalEntityID = configuration.totalEntityID,
                   !candidates.contains(where: { $0.id == totalEntityID }) {
                    Text(totalEntityID.rawValue).tag(MenuBarTotalMode.entity(totalEntityID))
                }
                ForEach(candidates, id: \.id.rawValue) { candidate in
                    Text(candidate.name).tag(MenuBarTotalMode.entity(candidate.id))
                }
            }
            .frame(width: 132)
            .accessibilityLabel("\(entity.name) gauge total source")
            if configuration.absoluteTotal != nil {
                Stepper(
                    "Total \(menuBarNumberLabel(configuration.absoluteTotal))",
                    value: menuBarAbsoluteTotalBinding(for: entity.id),
                    in: 1...100_000,
                    step: 1
                )
                .accessibilityLabel("\(entity.name) manual gauge total")
            }
        }
    }

    private func menuBarThresholdControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let thresholds = configuration.thresholds
        let steps = thresholds.steps.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("From each step's value upward the value wears the step's color; Base applies below every step.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    let highest = steps.first?.value ?? 0
                    var next = thresholds.steps
                    next.append(ThresholdStep(value: highest + 10, color: ValueThresholds.criticalColor))
                    model.setThresholds(entity.id, thresholds: ValueThresholds(steps: next, baseColor: thresholds.baseColor))
                } label: {
                    Label("Add threshold", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
                .accessibilityLabel("Add threshold for \(entity.name)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                thresholdStepRow(entity: entity, thresholds: thresholds, step: step, index: index)
            }

            // The Base row: the color below every step, like Grafana's Base.
            HStack(spacing: 8) {
                ColorPicker(
                    "Base color",
                    selection: thresholdBaseColorBinding(for: entity.id, thresholds: thresholds),
                    supportsOpacity: false
                )
                .labelsHidden()
                .frame(width: 34)
                .accessibilityLabel("\(entity.name) base threshold color")
                Text("Base")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if thresholds.baseColor != nil {
                    Button {
                        model.setThresholds(entity.id, thresholds: ValueThresholds(steps: thresholds.steps, baseColor: nil))
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PerchHACircularIconButtonStyle())
                    .controlSize(.small)
                    .help("Reset base to the default tint")
                    .accessibilityLabel("Reset \(entity.name) base threshold color")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One threshold step row, Grafana style: `[color well] >= [value] [delete]`.
    private func thresholdStepRow(
        entity: DiscoveredEntity,
        thresholds: ValueThresholds,
        step: ThresholdStep,
        index: Int
    ) -> some View {
        HStack(spacing: 8) {
            ColorPicker(
                "Threshold color",
                selection: thresholdStepColorBinding(for: entity.id, thresholds: thresholds, step: step),
                supportsOpacity: false
            )
            .labelsHidden()
            .frame(width: 34)
            .accessibilityLabel("\(entity.name) threshold \(index + 1) color")

            Text("\u{2265}")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ThresholdBoundField(
                placeholder: "value",
                value: step.value,
                onCommit: { newValue in
                    guard let newValue else {
                        return
                    }
                    var next = thresholds.steps
                    if let position = next.firstIndex(of: step) {
                        next[position] = ThresholdStep(value: newValue, color: step.color)
                    }
                    model.setThresholds(entity.id, thresholds: ValueThresholds(steps: next, baseColor: thresholds.baseColor))
                }
            )
            .frame(width: 72)
            .accessibilityLabel("\(entity.name) threshold \(index + 1) value")

            Spacer(minLength: 0)

            Button {
                var next = thresholds.steps
                if let position = next.firstIndex(of: step) {
                    next.remove(at: position)
                }
                model.setThresholds(entity.id, thresholds: ValueThresholds(steps: next, baseColor: thresholds.baseColor))
            } label: {
                Image(systemName: "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .help("Delete threshold")
            .accessibilityLabel("Delete \(entity.name) threshold \(index + 1)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func thresholdStepColorBinding(
        for id: EntityID,
        thresholds: ValueThresholds,
        step: ThresholdStep
    ) -> Binding<Color> {
        Binding(
            get: {
                PerchHATheme.color(for: step.color)
            },
            set: { newColor in
                guard let accent = PerchHAAccentColor(newColor) else {
                    return
                }
                var next = thresholds.steps
                if let position = next.firstIndex(of: step) {
                    next[position] = ThresholdStep(value: step.value, color: accent)
                }
                model.setThresholds(id, thresholds: ValueThresholds(steps: next, baseColor: thresholds.baseColor))
            }
        )
    }

    private func thresholdBaseColorBinding(
        for id: EntityID,
        thresholds: ValueThresholds
    ) -> Binding<Color> {
        Binding(
            get: {
                thresholds.baseColor.map(PerchHATheme.color(for:)) ?? PerchHATheme.accent
            },
            set: { newColor in
                guard let accent = PerchHAAccentColor(newColor) else {
                    return
                }
                model.setThresholds(id, thresholds: ValueThresholds(steps: thresholds.steps, baseColor: accent))
            }
        )
    }

    private func menuBarMoveButtons(for entity: DiscoveredEntity) -> some View {
        let promotedIDs = model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs
        let index = promotedIDs.firstIndex(of: entity.id)
        let canMoveUp = canReorderSelection && (index.map { $0 > promotedIDs.startIndex } ?? false)
        let canMoveDown = canReorderSelection && (index.map { $0 < promotedIDs.index(before: promotedIDs.endIndex) } ?? false)
        return HStack(spacing: 2) {
            Button {
                model.moveMenuBarEntity(entity.id, direction: .up)
            } label: {
                Image(systemName: "arrow.up.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))
            .accessibilityLabel("Move \(entity.name) earlier in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))

            Button {
                model.moveMenuBarEntity(entity.id, direction: .down)
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
            .accessibilityLabel("Move \(entity.name) later in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
        }
    }

    private func menuBarMoveHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.menuBarReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    @ViewBuilder
    private func selectionDragDrop<Row: View>(_ row: Row, item: SelectionDragItem) -> some View {
        if canReorderSelection {
            row
                .onDrag {
                    selectionDragProvider(item)
                }
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    applySelectionDrop(onto: item)
                }
        } else {
            row
        }
    }

    private func selectionDragProvider(_ item: SelectionDragItem) -> NSItemProvider {
        draggedSelectionItem = item
        return NSItemProvider(object: item.providerText as NSString)
    }

    private func applySelectionDrop(onto target: SelectionDragItem) -> Bool {
        guard canReorderSelection, let draggedSelectionItem, draggedSelectionItem != target else {
            self.draggedSelectionItem = nil
            return false
        }
        defer {
            self.draggedSelectionItem = nil
        }

        switch SelectionDropTranslator().translate(source: draggedSelectionItem, target: target, tree: settingsTree) {
        case let .room(sourceID, targetID, placement):
            return model.moveRoom(sourceID, relativeTo: targetID, placement: placement)
        case let .entity(sourceID, targetID, placement):
            return model.moveEntity(sourceID, relativeTo: targetID, placement: placement)
        case .unsupported:
            return false
        }
    }

    private func selectionMoveButtons(
        up: @escaping () -> Void,
        down: @escaping () -> Void,
        upLabel: String,
        downLabel: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: up) {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel(upLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel(downLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func moveControlHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.selectionReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    /// The Entities search binding. The field edits view-local state so every
    /// keystroke stays instant; the model (whose query change rebuilds the whole
    /// snapshot and re-renders every subscriber, including the open panel) is
    /// updated after a short debounce instead of per keypress.
    private var selectionSearchBinding: Binding<String> {
        Binding(
            get: {
                entitySearchText
            },
            set: { value in
                entitySearchText = value
                searchDebounceTask?.cancel()
                searchDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else {
                        return
                    }
                    model.updateSelectionQuery(value)
                }
            }
        )
    }

    private func selectionBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                if !model.snapshot.selectionConfiguration.isExplicit {
                    return true
                }
                return model.snapshot.selectionConfiguration.selectedEntityIDs.contains(id)
            },
            set: { isSelected in
                model.setEntity(id, isSelected: isSelected)
            }
        )
    }

    private func menuBarVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.isPromoted(id)
            },
            set: { isVisible in
                model.setMenuBarEntity(id, isVisible: isVisible)
            }
        )
    }

    private func menuBarStyleBinding(for id: EntityID) -> Binding<MenuBarDisplayStyle> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).style
            },
            set: { style in
                model.setMenuBarDisplayStyle(id, style: style)
            }
        )
    }

    /// The per-entity menu-bar appearance binding. Reads the per-entity override
    /// when set, otherwise the global default; writing always sets a per-entity
    /// override so the choice wins over the global default for this entity.
    private func menuBarItemAppearanceBinding(for id: EntityID) -> Binding<PerchHAMenuBarAppearance> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).appearance
                    ?? displayPreferences.menuBarAppearance
            },
            set: { appearance in
                model.setMenuBarAppearance(id, appearance: appearance)
            }
        )
    }

    private func coverControlModeBinding(for id: EntityID) -> Binding<CoverControlMode> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).coverControlMode
            },
            set: { mode in
                model.setCoverControlMode(id, mode: mode)
            }
        )
    }

    private func displayUnitBinding(for id: EntityID) -> Binding<ValueUnit?> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).displayUnit
            },
            set: { unit in
                model.setDisplayUnit(id, displayUnit: unit)
            }
        )
    }

    private func displayMinBinding(for id: EntityID) -> Binding<String> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).minValue
                    .map { PerchHABoundsField.text(for: $0) } ?? ""
            },
            set: { text in
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                model.setDisplayBounds(id, minValue: PerchHABoundsField.value(from: text), maxValue: configuration.maxValue)
            }
        )
    }

    private func displayMaxBinding(for id: EntityID) -> Binding<String> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).maxValue
                    .map { PerchHABoundsField.text(for: $0) } ?? ""
            },
            set: { text in
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                model.setDisplayBounds(id, minValue: configuration.minValue, maxValue: PerchHABoundsField.value(from: text))
            }
        )
    }

    private func menuBarLabelBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsLabel
            },
            set: { showsLabel in
                model.setMenuBarShowsLabel(id, showsLabel: showsLabel)
            }
        )
    }

    private func menuBarUnitBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsUnit
            },
            set: { showsUnit in
                model.setMenuBarShowsUnit(id, showsUnit: showsUnit)
            }
        )
    }

    private func menuBarDecimalsBinding(for id: EntityID) -> Binding<Int> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).maximumFractionDigits
            },
            set: { maximumFractionDigits in
                model.setMenuBarMaximumFractionDigits(id, maximumFractionDigits: maximumFractionDigits)
            }
        )
    }

    private func menuBarHistoryRangeBinding(for id: EntityID) -> Binding<HistoryRange?> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
            },
            set: { range in
                model.setMenuBarDefaultHistoryRange(id, defaultHistoryRange: range)
            }
        )
    }

    private func menuBarTotalModeBinding(for id: EntityID) -> Binding<MenuBarTotalMode> {
        Binding(
            get: {
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                if let totalEntityID = configuration.totalEntityID {
                    return .entity(totalEntityID)
                }
                if configuration.absoluteTotal != nil {
                    return .absolute
                }
                return .none
            },
            set: { mode in
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                switch mode {
                case .none:
                    model.setMenuBarTotalEntityID(id, totalEntityID: nil)
                case .absolute:
                    model.setMenuBarAbsoluteTotal(id, total: configuration.absoluteTotal ?? 100)
                case let .entity(totalEntityID):
                    model.setMenuBarTotalEntityID(id, totalEntityID: totalEntityID)
                }
            }
        )
    }

    private func menuBarAbsoluteTotalBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).absoluteTotal ?? 100
            },
            set: { total in
                model.setMenuBarAbsoluteTotal(id, total: max(1, total))
            }
        )
    }

    private func menuBarTotalCandidates(for source: DiscoveredEntity) -> [DiscoveredEntity] {
        model.snapshot.availableRooms
            .flatMap(\.entities)
            .filter { entity in
                entity.id != source.id
                    && menuBarNumericState(entity.state) != nil
                    && menuBarUnitsAreCompatible(source.unit, entity.unit)
            }
    }

    private func menuBarCanUseGaugeTotal(for entity: DiscoveredEntity) -> Bool {
        menuBarNumericState(entity.state) != nil && !menuBarIsPercentUnit(entity.unit)
    }

    private func menuBarNumericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func menuBarIsPercentUnit(_ unit: String?) -> Bool {
        menuBarNormalizedUnit(unit) == "%"
    }

    private func menuBarUnitsAreCompatible(_ sourceUnit: String?, _ totalUnit: String?) -> Bool {
        menuBarNormalizedUnit(sourceUnit) == menuBarNormalizedUnit(totalUnit)
    }

    private func menuBarNormalizedUnit(_ unit: String?) -> String? {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

/// A grouped count of entities sharing one unhealthy status, for the
/// Diagnostics entity-health summary.
private struct EntityHealthGroup {
    let label: String
    let count: Int
    let systemImage: String
}

/// A deduped, capped report of unhealthy visible entities for Diagnostics.
///
/// `warningCount` matches the dashboard summary's count of
/// unavailable/unknown/stale values. `visibleGroups` is capped so a large fleet
/// shows a short summary; `hiddenCount` carries the remainder behind an "and N
/// more" affordance.
private struct EntityHealthReport {
    let totalVisible: Int
    let warningCount: Int
    let visibleGroups: [EntityHealthGroup]
    let hiddenCount: Int
}

/// Locale-independent parsing and display for the per-entity min/max bound
/// fields. Empty or unparsable text clears the bound.
private enum PerchHABoundsField {
    static func value(from text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Double(trimmed)
    }

    static func text(for value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// The curated SF Symbol catalog offered by the per-entity dashboard icon
/// picker, grouped by home-automation theme. Symbols are limited to names
/// available on macOS 13 so a picked icon always renders.
public enum PerchHAEntityIconCatalog {
    /// One themed group of the picker.
    public struct Section: Sendable {
        public let title: String
        public let symbols: [String]
    }

    /// The picker's sections, in display order.
    public static let sections: [Section] = [
        Section(title: "Climate", symbols: [
            "thermometer.medium", "thermometer.sun", "thermometer.snowflake", "humidity",
            "wind", "snowflake", "flame", "drop", "drop.degreesign", "sun.max", "moon", "cloud.rain"
        ]),
        Section(title: "Energy & power", symbols: [
            "bolt", "bolt.fill", "bolt.circle", "bolt.slash", "battery.100", "battery.50",
            "battery.25", "powerplug", "poweroutlet.type.f", "gauge.with.dots.needle.67percent", "leaf", "ev.charger"
        ]),
        Section(title: "Lights & switches", symbols: [
            "lightbulb", "lightbulb.fill", "lightbulb.2", "lamp.desk", "lamp.floor",
            "lamp.ceiling", "light.recessed", "switch.2", "togglepower", "dial.low", "dial.high"
        ]),
        Section(title: "Security & access", symbols: [
            "lock", "lock.open", "lock.shield", "key", "shield", "shield.checkered",
            "eye", "video", "bell", "bell.badge", "exclamationmark.triangle", "hand.raised"
        ]),
        Section(title: "Doors, windows & covers", symbols: [
            "door.left.hand.closed", "door.left.hand.open", "door.garage.closed", "door.garage.open",
            "window.vertical.closed", "window.vertical.open", "blinds.vertical.closed", "blinds.horizontal.closed",
            "curtains.closed", "curtains.open"
        ]),
        Section(title: "Rooms & appliances", symbols: [
            "sofa", "bed.double", "bathtub", "shower", "toilet", "refrigerator", "oven",
            "microwave", "dishwasher", "washer", "dryer", "stove", "sink", "chair.lounge"
        ]),
        Section(title: "Media & network", symbols: [
            "tv", "hifispeaker", "homepod", "music.note", "speaker.wave.2", "wifi",
            "wifi.router", "antenna.radiowaves.left.and.right", "network", "server.rack", "externaldrive", "printer"
        ]),
        Section(title: "Motion & presence", symbols: [
            "figure.walk", "figure.run", "person", "person.2", "person.3", "pawprint",
            "car", "bicycle", "location", "map", "house", "building.2"
        ]),
        Section(title: "Measurements", symbols: [
            "gauge.medium", "speedometer", "chart.line.uptrend.xyaxis", "chart.bar", "waveform.path.ecg",
            "timer", "clock", "calendar", "number", "percent", "ruler", "scalemass"
        ]),
        Section(title: "General", symbols: [
            "sensor.tag.radiowaves.forward", "dot.radiowaves.left.and.right", "cpu", "memorychip",
            "fanblades", "sparkles", "star", "heart", "checkmark.circle", "xmark.circle", "questionmark.circle", "info.circle"
        ])
    ]

    /// Every symbol in the catalog, flattened in section order.
    public static var allSymbols: [String] {
        sections.flatMap(\.symbols)
    }
}

/// A numeric threshold bound editor: commits on Return or focus loss, an empty
/// field means an open bound, and non-numeric input restores the prior value.
struct ThresholdBoundField: View {
    let placeholder: String
    let value: Double?
    let onCommit: (Double?) -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .focused($isFocused)
            .onAppear {
                text = Self.label(for: value)
            }
            .onChange(of: value) { newValue in
                if !isFocused {
                    text = Self.label(for: newValue)
                }
            }
            .onSubmit(commit)
            .onChange(of: isFocused) { focused in
                if !focused {
                    commit()
                }
            }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            onCommit(nil)
            return
        }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized) {
            onCommit(parsed)
        } else {
            text = Self.label(for: value)
        }
    }

    private static func label(for value: Double?) -> String {
        guard let value else {
            return ""
        }
        if value == value.rounded() && abs(value) < 1_000_000_000 {
            return String(Int(value))
        }
        return String(value)
    }
}
