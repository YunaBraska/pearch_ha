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

            VStack(alignment: .leading, spacing: 4) {
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
                PerchHANativeTextField(
                    placeholder: "Fallback URL",
                    text: fallbackURLBinding,
                    contentType: {
                        if #available(macOS 14.0, *) {
                            return .URL
                        }
                        return nil
                    }(),
                    normalizeOnCommit: PerchHAConnectionForm.normalizedHomeAssistantURLString
                )
                Text("Optional remote or backup address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

            Button("Sign out") {
                model.signOut()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Disconnect and clear the stored session. The address is kept so you can reconnect.")
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

    @ViewBuilder
    private func connectionMessage(
        _ message: String,
        hint: String?,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityPrefix): \(message)\(hint.map { ". \($0)" } ?? "")")
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

    private var fallbackURLBinding: Binding<String> {
        Binding(
            get: { model.snapshot.connectionForm.fallbackURLString },
            set: { value in
                model.updateConnectionForm(fallbackURLString: value)
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
    /// Selectable tabs of the Settings window.
    public enum Tab: Hashable, Sendable {
        case connection
        case entities
        case about
    }

    @ObservedObject private var model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var selectedTab: Tab
    @State private var expandedEntityIDs: Set<EntityID>
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

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
        initiallyExpandedEntityIDs: Set<EntityID> = []
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        _selectedTab = State(initialValue: initialTab)
        _expandedEntityIDs = State(initialValue: initiallyExpandedEntityIDs)
    }

    public var body: some View {
        let accessibility = PerchHAPanelView.rootAccessibilityPresentation(
            snapshot: model.snapshot,
            preferences: accessibilityPreferences
        )
        TabView(selection: $selectedTab) {
            connectionTab
                .tabItem {
                    Label("Connection", systemImage: "network")
                }
                .tag(Tab.connection)
            entitiesTab
                .tabItem {
                    Label("Entities", systemImage: "square.grid.2x2")
                }
                .tag(Tab.entities)
            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(Tab.about)
        }
        .frame(minWidth: 520, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .contrast(accessibility.contrastPolicy == .increased ? 1.12 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .transaction { transaction in
            if accessibility.motionPolicy == .reduced {
                transaction.animation = nil
            }
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
        case .connection: AnyView(connectionTab)
        case .entities: AnyView(entitiesTab)
        case .about: AnyView(aboutTab)
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .contrast(accessibilityPreferences.contrastPolicy == .increased ? 1.12 : 1)
    }

    private var connectionTab: some View {
        ScrollView(.vertical) {
            PerchHACard(cornerRadius: 12) {
                PerchHAConnectionFormFields(model: model)
                    .textFieldStyle(.roundedBorder)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .tint(PerchHATheme.accent)
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            PerchHACard(cornerRadius: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "house.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(PerchHATheme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PearchHA")
                                .font(.title2.weight(.semibold))
                            Text("Version \(Self.applicationVersion)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("A quiet macOS menu-bar companion for Home Assistant: scan room values at a glance, drive switches and covers, and run saved service calls without opening a browser.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
            Spacer(minLength: 0)
        }
        .tint(PerchHATheme.accent)
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                HStack(spacing: 5) {
                    Text(room.name.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                        .lineLimit(1)
                    Spacer(minLength: 0)
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
                .padding(.horizontal, 4),
                item: .room(room.id)
            )
            PerchHACard(cornerRadius: 12) {
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
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            } icon: {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PerchHATheme.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
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
