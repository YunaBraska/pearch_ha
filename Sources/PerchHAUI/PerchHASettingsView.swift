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
/// the failure/progress banners, and the sign-in/connect buttons, mirroring the
/// current first-run design. The app always trusts the entered Home Assistant
/// host, so there is no certificate-trust control.
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
        }
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
        case dashboard
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
            case .dashboard: "Dashboard"
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
            case .dashboard: "rectangle.grid.1x2"
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
    @State private var expandedEntityIDs: Set<EntityID>
    @State private var displayPreferences: PerchHADisplayPreferences
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
        _expandedEntityIDs = State(initialValue: initiallyExpandedEntityIDs)
        _displayPreferences = State(initialValue: displayPreferencesProvider())
        _launchAtLogin = State(initialValue: launchAtLoginProvider())
    }

    public var body: some View {
        let accessibility = PerchHAPanelView.rootAccessibilityPresentation(
            snapshot: model.snapshot,
            preferences: accessibilityPreferences
        )
        HStack(spacing: 0) {
            sidebarRail
            Divider()
                .accessibilityHidden(true)
            detailContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        }
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
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            HStack(spacing: PerchHASpacing.sm) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20, alignment: .center)
                Text(tab.title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, PerchHASpacing.sm)
            .padding(.vertical, PerchHASpacing.sm - 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isSelected ? PerchHATheme.accent : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous)
                    .fill(isSelected ? PerchHATheme.accent.opacity(0.16) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: PerchHACornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The rail's elevated surface fill, resolved against the current appearance
    /// so it reads as a distinct rail in both light and dark.
    private var railBackground: Color {
        PerchHATheme.Dashboard.palette(colorScheme).cardBackgroundElevated
    }

    /// Routes a section to its detail content.
    @ViewBuilder
    private func detailContent(for tab: Tab) -> some View {
        switch tab {
        case .general: generalTab
        case .connection: connectionTab
        case .dashboard: dashboardTab
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
        case .dashboard: AnyView(dashboardTab)
        case .entities: AnyView(entitiesTab)
        case .appearance: AnyView(appearanceTab)
        case .diagnostics: AnyView(diagnosticsTab)
        case .privacy: AnyView(privacyTab)
        case .about: AnyView(aboutTab)
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .contrast(accessibilityPreferences.contrastPolicy == .increased ? 1.12 : 1)
    }

    private var connectionTab: some View {
        settingsPage(title: "Connection", systemImage: Tab.connection.systemImage) {
            settingsCard {
                PerchHAConnectionFormFields(model: model)
                    .textFieldStyle(.roundedBorder)
            }
        }
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
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PerchHASpacing.md + 2) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                content()
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, PerchHASpacing.lg)
            .padding(.horizontal, PerchHASpacing.lg + 2)
        }
        .tint(PerchHATheme.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A grouped settings card with consistent interior padding, so no raw
    /// ungrouped form rows are drawn anywhere.
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        PerchHACard(cornerRadius: PerchHACornerRadius.card) {
            VStack(alignment: .leading, spacing: PerchHASpacing.md) {
                content()
            }
            .padding(PerchHASpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                            .toggleStyle(.checkbox)
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
        }
    }

    // MARK: Dashboard

    /// Dashboard-facing menu-bar configuration: a per-entity editor where each
    /// entity can be shown in the menu bar and given its own icon/text/both
    /// appearance, plus the global stable-width preference. The per-entity
    /// appearance overrides the global default for that entity.
    private var dashboardTab: some View {
        settingsPage(title: "Dashboard", systemImage: Tab.dashboard.systemImage) {
            settingsCard {
                settingsSection(title: "Menu bar items", systemImage: "menubar.rectangle") {
                    menuBarItemsEditor
                }
            }
            settingsCard {
                settingsSection(title: "Width", systemImage: "ruler") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Keep a stable width", isOn: stableMenuBarWidthBinding)
                            .toggleStyle(.checkbox)
                            .fixedSize()
                            .accessibilityLabel("Keep a stable menu bar width")
                        Text("Uses monospaced digits so the value does not shift as it changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// The entities offered in the Dashboard menu-bar editor: promoted entities
    /// first (in their menu-bar order), then the remaining available entities.
    private var menuBarEditorEntities: [DiscoveredEntity] {
        let entities = model.snapshot.availableRooms.flatMap(\.entities)
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let promotedIDs = model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs
        let promoted = promotedIDs.compactMap { byID[$0] }
        let promotedSet = Set(promotedIDs)
        let remaining = entities.filter { !promotedSet.contains($0.id) }
        return promoted + remaining
    }

    @ViewBuilder
    private var menuBarItemsEditor: some View {
        let entities = menuBarEditorEntities
        if entities.isEmpty {
            Text("Connect to Home Assistant to choose which entities appear in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Choose which entities appear in the menu bar and how each one looks.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(entities, id: \.id.rawValue) { entity in
                    menuBarItemRow(for: entity)
                    if entity.id != entities.last?.id {
                        settingsSectionDivider
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func menuBarItemRow(for entity: DiscoveredEntity) -> some View {
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(entity.name, isOn: menuBarVisibilityBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .accessibilityLabel("Show \(entity.name) in menu bar")
                Spacer(minLength: 0)
                if isPromoted {
                    menuBarMoveButtons(for: entity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isPromoted {
                settingsControlRow("Show") {
                    Picker("Show", selection: menuBarItemAppearanceBinding(for: entity.id)) {
                        ForEach(PerchHAMenuBarAppearance.allCases, id: \.rawValue) { appearance in
                            Text(appearance.displayName).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("\(entity.name) menu bar appearance")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Appearance

    /// Appearance: the live preview plus the theme/accent controls, which share
    /// their bindings (and persistence) with the General section, and a reset to
    /// the shipped display-preference defaults.
    private var appearanceTab: some View {
        settingsPage(title: "Appearance", systemImage: Tab.appearance.systemImage) {
            settingsCard {
                settingsSection(title: "Preview", systemImage: "eye") {
                    PerchHAAppearancePreview(preferences: displayPreferences)
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
    /// a deduped, capped list of affected entities), the last-updated timestamp,
    /// and the read-only history-prefetch reference. Refresh is automatic, so no
    /// manual refresh control is offered. All values come from the live snapshot;
    /// nothing is fabricated.
    private var diagnosticsTab: some View {
        let health = entityHealth
        return settingsPage(title: "Diagnostics", systemImage: Tab.diagnostics.systemImage) {
            settingsCard {
                settingsSection(title: "Connection", systemImage: "antenna.radiowaves.left.and.right") {
                    diagnosticsConnectionContent
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
                settingsSection(title: "History prefetch", systemImage: "chart.line.uptrend.xyaxis") {
                    diagnosticsPrefetchContent
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

    /// The updates diagnostic: a read-only last-updated description. Refresh is
    /// automatic (on open, periodically while open, and via live WebSocket push),
    /// so there is no manual refresh control here.
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var diagnosticsPrefetchContent: some View {
        let prefetch = PerchHAHistoryPrefetchConfiguration()
        return VStack(alignment: .leading, spacing: 6) {
            settingsControlRow("Lookahead") {
                Text("\(prefetch.lookahead) values")
                    .foregroundStyle(.secondary)
            }
            settingsControlRow("Settle delay") {
                Text("\(prefetch.settleDelay.nanoseconds / 1_000_000) ms")
                    .foregroundStyle(.secondary)
            }
            Text("How far ahead PearchHA warms inline charts when the panel is open. These are tuned defaults shown for reference.")
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
        settingsView
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settingsView: some View {
        ScrollView(.vertical) {
            settingsContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            if !model.orphanedCustomActions.isEmpty {
                orphanedCustomActionControls
            }
            if model.snapshot.selectionTree.isEmpty {
                Text("No matching values.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(settingsTree.enumerated()), id: \.element.id.rawValue) { index, room in
                        selectionRoom(
                            room,
                            canMoveUp: canReorderSelection && index > settingsTree.startIndex,
                            canMoveDown: canReorderSelection && index < settingsTree.index(before: settingsTree.endIndex)
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
        model.snapshot.selectionTree
    }

    private var canReorderSelection: Bool {
        model.snapshot.canReorderSelectionWithKeyboard
    }

    private func selectionRoom(_ room: SelectableRoom, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            selectionDragDrop(
                PerchHASectionHeader(room.name) {
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
                .padding(.horizontal, PerchHASpacing.xs),
                item: .room(room.id)
            )
            PerchHACard(cornerRadius: PerchHACornerRadius.card) {
                VStack(spacing: 0) {
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
                            Divider()
                                .padding(.leading, 34)
                        }
                    }
                }
            }
        }
    }

    private func selectionEntityRow(
        _ selectable: SelectableEntity,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        let entity = selectable.entity
        let isExpanded = expandedEntityIDs.contains(entity.id)
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Toggle("", isOn: selectionBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .accessibilityLabel("Show \(entity.name) in panel")
                Image(systemName: perchHAEntityIconName(for: entity))
                    .font(.system(size: 14))
                    .frame(width: 22, alignment: .center)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(entity.name)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isPromoted {
                    Circle()
                        .fill(PerchHATheme.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel("\(entity.name) shown in menu bar")
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
                    toggleEntityExpansion(entity.id)
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
            if isExpanded {
                entityDetailSections(for: entity)
                    .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private func toggleEntityExpansion(_ id: EntityID) {
        if expandedEntityIDs.contains(id) {
            expandedEntityIDs.remove(id)
        } else {
            expandedEntityIDs.insert(id)
        }
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
                settingsSection(title: "Alerts", systemImage: "bell.badge") {
                    menuBarThresholdControls(for: entity, configuration: configuration)
                }
            }
            settingsSectionDivider
            settingsSection(title: "Buttons", systemImage: "hand.tap") {
                customActionControls(for: entity)
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

            if isPromoted {
                HStack(spacing: 12) {
                    Toggle("Show label", isOn: menuBarLabelBinding(for: entity.id))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) label in menu bar")
                    Toggle("Show unit", isOn: menuBarUnitBinding(for: entity.id))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) unit in menu bar")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Stepper(
                        "Decimals \(configuration.maximumFractionDigits)",
                        value: menuBarDecimalsBinding(for: entity.id),
                        in: 0...3
                    )
                    .fixedSize()
                    .accessibilityLabel("\(entity.name) decimals")
                    Picker("History", selection: menuBarHistoryRangeBinding(for: entity.id)) {
                        ForEach(HistoryRange.allCases, id: \.rawValue) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 86)
                    .accessibilityLabel("\(entity.name) default history range")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if configuration.style != .text && menuBarCanUseGaugeTotal(for: entity) {
                    menuBarTotalControls(for: entity, configuration: configuration)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Menu bar section: whether the entity is shown in the menu bar and its
    /// position there.
    private func menuBarSectionControls(for entity: DiscoveredEntity, isPromoted: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle("Show in menu bar", isOn: menuBarVisibilityBinding(for: entity.id))
                .toggleStyle(.checkbox)
                .fixedSize()
                .accessibilityLabel("Show \(entity.name) in menu bar")
            if isPromoted {
                menuBarMoveButtons(for: entity)
            }
            Spacer(minLength: 0)
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

    /// Guided, jargon-free Buttons editor for an entity.
    ///
    /// Each button exposes only a Name field, a "What it does" picker (friendly
    /// service labels grouped by domain), an optional Target picker, an "Ask
    /// before running" toggle, reorder controls, and delete. When no service
    /// metadata is available the picker and Add button are disabled with a short
    /// hint, so the editor never falls back to raw Home Assistant fields.
    private func customActionControls(for entity: DiscoveredEntity) -> some View {
        let actions = model.customActions(for: entity)
        let hasMetadata = !model.snapshot.serviceMetadata.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("One-tap buttons attached to this value.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    addCustomAction(for: entity)
                } label: {
                    Label("Add button", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(PerchHAIconButtonStyle(prominentOnHover: true))
                .disabled(!hasMetadata)
                .help(hasMetadata ? "Add button" : "Connect to Home Assistant to add a button")
                .accessibilityLabel("Add button for \(entity.name)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !hasMetadata && actions.isEmpty {
                Text("Connect to Home Assistant to add a button.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(actions.enumerated()), id: \.element.id.rawValue) { index, action in
                customActionEditor(
                    action,
                    entity: entity,
                    hasMetadata: hasMetadata,
                    canMoveUp: canReorderSelection && index > actions.startIndex,
                    canMoveDown: canReorderSelection && index < actions.index(before: actions.endIndex)
                )
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    private func customActionEditor(
        _ action: EntityCustomAction,
        entity: DiscoveredEntity,
        hasMetadata: Bool,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Name", text: customActionTitleBinding(for: action.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(entity.name) button name")
                customActionMoveButtons(
                    for: action,
                    entityName: entity.name,
                    canMoveUp: canMoveUp,
                    canMoveDown: canMoveDown
                )
                Button {
                    model.removeCustomAction(action.id)
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(PerchHACircularIconButtonStyle())
                .controlSize(.small)
                .help("Delete button")
                .accessibilityLabel("Delete \(action.title)")
            }

            settingsControlRow("What it does") {
                customActionServicePicker(action, hasMetadata: hasMetadata)
            }

            settingsControlRow("Target") {
                customActionTargetPicker(action)
            }

            Toggle("Ask before running", isOn: customActionConfirmationBinding(for: action.id))
                .toggleStyle(.checkbox)
                .fixedSize()
                .accessibilityLabel("\(action.title) ask before running")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The "What it does" picker: friendly service labels grouped by domain, or
    /// a single disabled placeholder when no metadata is available.
    @ViewBuilder
    private func customActionServicePicker(_ action: EntityCustomAction, hasMetadata: Bool) -> some View {
        if hasMetadata {
            Picker("What it does", selection: customActionServiceSelectionBinding(for: action.id)) {
                let current = ServiceSelection(domain: action.action.domain, service: action.action.service)
                if !metadataContains(current) {
                    Text(PerchHAServiceLabel.friendlyLabel(domain: current.domain, service: current.service))
                        .tag(current)
                }
                ForEach(metadataDomains, id: \.self) { domain in
                    Section(PerchHAServiceLabel.domainTitle(domain)) {
                        ForEach(metadataServices(for: domain), id: \.service) { metadata in
                            Text(PerchHAServiceLabel.friendlyLabel(domain: domain, service: metadata.service))
                                .tag(ServiceSelection(domain: domain, service: metadata.service))
                        }
                    }
                }
            }
            .labelsHidden()
            .frame(width: 200)
            .accessibilityLabel("\(action.title) what it does")
        } else {
            Picker("What it does", selection: .constant(0)) {
                Text("Connect to Home Assistant to choose…").tag(0)
            }
            .labelsHidden()
            .frame(width: 200)
            .disabled(true)
            .accessibilityLabel("\(action.title) what it does")
        }
    }

    /// The optional Target picker: discovered entities by friendly name, plus a
    /// "None" choice.
    private func customActionTargetPicker(_ action: EntityCustomAction) -> some View {
        let entities = discoveredEntitiesForTarget
        return Picker("Target", selection: customActionTargetSelectionBinding(for: action.id)) {
            Text("None").tag(EntityID?.none)
            if let current = action.action.targetEntityID,
               !entities.contains(where: { $0.id == current }) {
                Text(current.rawValue).tag(EntityID?.some(current))
            }
            ForEach(entities, id: \.id.rawValue) { entity in
                Text(entity.name).tag(EntityID?.some(entity.id))
            }
        }
        .labelsHidden()
        .frame(width: 200)
        .accessibilityLabel("\(action.title) target")
    }

    private var discoveredEntitiesForTarget: [DiscoveredEntity] {
        model.snapshot.availableRooms.flatMap(\.entities)
    }

    private func metadataContains(_ selection: ServiceSelection) -> Bool {
        model.snapshot.serviceMetadata.contains {
            $0.domain == selection.domain && $0.service == selection.service
        }
    }

    /// A combined domain+service choice for the "What it does" picker, so a
    /// single selection sets both the action's `domain` and `service`.
    private struct ServiceSelection: Hashable {
        let domain: String
        let service: String
    }

    private func customActionServiceSelectionBinding(for id: CustomActionID) -> Binding<ServiceSelection> {
        Binding(
            get: {
                let action = model.customAction(id: id)
                return ServiceSelection(
                    domain: action?.action.domain ?? "",
                    service: action?.action.service ?? ""
                )
            },
            set: { selection in
                model.setCustomActionService(id, domain: selection.domain, service: selection.service)
            }
        )
    }

    private func customActionTargetSelectionBinding(for id: CustomActionID) -> Binding<EntityID?> {
        Binding(
            get: {
                model.customAction(id: id)?.action.targetEntityID
            },
            set: { targetEntityID in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: action.action.domain,
                            service: action.action.service,
                            targetEntityID: targetEntityID,
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionMoveButtons(
        for action: EntityCustomAction,
        entityName: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        HStack(spacing: 2) {
            Button {
                model.moveCustomAction(action.id, direction: .up)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel("Move \(action.title) earlier for \(entityName)")
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button {
                model.moveCustomAction(action.id, direction: .down)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PerchHACircularIconButtonStyle())
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel("Move \(action.title) later for \(entityName)")
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func addCustomAction(for entity: DiscoveredEntity) {
        guard let firstDomain = metadataDomains.first,
              let firstService = metadataServices(for: firstDomain).first else {
            return
        }
        let action = EntityCustomAction(
            id: nextCustomActionID(for: entity.id),
            entityID: entity.id,
            title: PerchHAServiceLabel.serviceTitle(firstService.service),
            action: ActionSpec(
                domain: firstDomain,
                service: firstService.service,
                targetEntityID: nil
            )
        )
        model.setCustomAction(action)
    }


    private var metadataDomains: [String] {
        Array(Set(model.snapshot.serviceMetadata.map(\.domain))).sorted()
    }

    private func metadataServices(for domain: String) -> [HAServiceMetadata] {
        model.snapshot.serviceMetadata
            .filter { $0.domain == domain }
            .sorted { lhs, rhs in lhs.service < rhs.service }
    }



    private func nextCustomActionID(for entityID: EntityID) -> CustomActionID {
        let base = "action-\(entityID.rawValue.replacingOccurrences(of: ".", with: "-"))"
        var index = 1
        var id = CustomActionID("\(base)-\(index)")
        while model.customAction(id: id) != nil {
            index += 1
            id = CustomActionID("\(base)-\(index)")
        }
        return id
    }

    private func customActionTitleBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.title ?? ""
            },
            set: { title in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: title,
                        action: action.action,
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionConfirmationBinding(for id: CustomActionID) -> Binding<Bool> {
        Binding(
            get: {
                model.customAction(id: id)?.requiresConfirmation ?? false
            },
            set: { requiresConfirmation in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: action.action,
                        requiresConfirmation: requiresConfirmation
                    )
                }
            }
        )
    }

    private func updateCustomAction(
        _ id: CustomActionID,
        transform: (EntityCustomAction) -> EntityCustomAction
    ) {
        guard let action = model.customAction(id: id) else {
            return
        }
        model.setCustomAction(transform(action))
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("Warning", isOn: menuBarWarningEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) warning threshold")
                if configuration.thresholds.warning != nil {
                    Picker("Warning", selection: menuBarWarningDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) warning threshold direction")
                    Stepper(
                        "Warning \(menuBarNumberLabel(configuration.thresholds.warning?.value))",
                        value: menuBarWarningValueBinding(for: entity.id),
                        in: -100_000...100_000,
                        step: 1
                    )
                    .accessibilityLabel("\(entity.name) warning threshold value")
                }
            }
            HStack(spacing: 8) {
                Toggle("Critical", isOn: menuBarCriticalEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) critical threshold")
                if configuration.thresholds.critical != nil {
                    Picker("Critical", selection: menuBarCriticalDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) critical threshold direction")
                    Stepper(
                        "Critical \(menuBarNumberLabel(configuration.thresholds.critical?.value))",
                        value: menuBarCriticalValueBinding(for: entity.id),
                        in: -100_000...100_000,
                        step: 1
                    )
                    .accessibilityLabel("\(entity.name) critical threshold value")
                }
            }
        }
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

    private var selectionSearchBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.selectionQuery
            },
            set: { value in
                model.updateSelectionQuery(value)
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

    private func menuBarHistoryRangeBinding(for id: EntityID) -> Binding<HistoryRange> {
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

    private func menuBarWarningEnabledBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning != nil
            },
            set: { isEnabled in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: isEnabled
                        ? ValueThreshold(value: current?.value ?? 80, direction: current?.direction ?? .aboveOrEqual)
                        : nil
                )
            }
        )
    }

    private func menuBarWarningValueBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning?.value ?? 80
            },
            set: { value in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: ValueThreshold(value: value, direction: current?.direction ?? .aboveOrEqual)
                )
            }
        )
    }

    private func menuBarWarningDirectionBinding(for id: EntityID) -> Binding<ValueThresholdDirection> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning?.direction
                    ?? .aboveOrEqual
            },
            set: { direction in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: ValueThreshold(value: current?.value ?? 80, direction: direction)
                )
            }
        )
    }

    private func menuBarCriticalEnabledBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical != nil
            },
            set: { isEnabled in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: isEnabled
                        ? ValueThreshold(value: current?.value ?? 90, direction: current?.direction ?? .aboveOrEqual)
                        : nil
                )
            }
        )
    }

    private func menuBarCriticalValueBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical?.value ?? 90
            },
            set: { value in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: ValueThreshold(value: value, direction: current?.direction ?? .aboveOrEqual)
                )
            }
        )
    }

    private func menuBarCriticalDirectionBinding(for id: EntityID) -> Binding<ValueThresholdDirection> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical?.direction
                    ?? .aboveOrEqual
            },
            set: { direction in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: ValueThreshold(value: current?.value ?? 90, direction: direction)
                )
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
