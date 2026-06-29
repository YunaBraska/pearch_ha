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
/// current first-run design. The self-signed certificate toggle is rendered, in
/// an "Advanced" disclosure group, only when `includesSelfSignedToggle` is true so
/// the first-run panel keeps its inline toggle while the Settings window hosts the
/// toggle in its Advanced tab instead.
struct PerchHAConnectionFormFields: View {
    @ObservedObject var model: PerchHAPanelModel
    let includesSelfSignedToggle: Bool

    var body: some View {
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

            if includesSelfSignedToggle {
                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Allow self-signed certificates for these hosts",
                            isOn: selfSignedCertificateBinding
                        )
                        Text("Only enable this if you connect over HTTPS with your own certificate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }
        }
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
            return "If you use a self-signed certificate, enable it under Advanced."
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
            get: {
                model.snapshot.showsConnectedContent ? "" : model.snapshot.connectionForm.urlString
            },
            set: { value in
                model.updateConnectionForm(urlString: value)
            }
        )
    }

    private var fallbackURLBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.showsConnectedContent ? "" : model.snapshot.connectionForm.fallbackURLString
            },
            set: { value in
                model.updateConnectionForm(fallbackURLString: value)
            }
        )
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.showsConnectedContent ? "" : model.tokenInputForView
            },
            set: { value in
                model.updateConnectionForm(token: value)
            }
        )
    }

    private var selfSignedCertificateBinding: Binding<Bool> {
        Binding(
            get: {
                model.snapshot.connectionForm.allowsSelfSignedCertificates
            },
            set: { value in
                model.updateConnectionForm(allowsSelfSignedCertificates: value)
            }
        )
    }
}

/// Dedicated, resizable Settings window content for PerchHA.
///
/// Organized as a `TabView` with four tabs: Connection, Entities, Advanced, and
/// About. Per-entity display and action configuration stays inline inside the
/// Entities tree, matching the documented UX. This view hosts the settings-only
/// controls relocated out of the cramped menu-bar panel.
public struct PerchHASettingsView: View {
    private enum CustomActionEditorLayout {
        static let serviceDataTypePickerWidth: CGFloat = 92
        static let serviceDataValueMinWidth: CGFloat = 144
    }

    /// Selectable tabs of the Settings window.
    public enum Tab: Hashable, Sendable {
        case connection
        case entities
        case advanced
        case about
    }

    @ObservedObject private var model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var selectedTab: Tab
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil,
        initialTab: Tab = .connection
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        _selectedTab = State(initialValue: initialTab)
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
            advancedTab
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(Tab.advanced)
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
        case .advanced: AnyView(advancedTab)
        case .about: AnyView(aboutTab)
        }
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .contrast(accessibilityPreferences.contrastPolicy == .increased ? 1.12 : 1)
    }

    private var connectionTab: some View {
        ScrollView {
            PerchHAConnectionFormFields(model: model, includesSelfSignedToggle: false)
                .textFieldStyle(.roundedBorder)
                .padding(14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var advancedTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(
                "Self-signed cert for current HTTPS hosts",
                isOn: selfSignedCertificateBinding
            )
            Text("Allow self-signed TLS certificates for the configured HTTPS Home Assistant hosts. Leave this off unless your Home Assistant uses a certificate that macOS does not already trust.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PerchHA")
                .font(.title2.weight(.semibold))
            Text("Version \(Self.applicationVersion)")
                .foregroundStyle(.secondary)
            Text("A quiet macOS menu-bar companion for Home Assistant: scan room values at a glance, drive switches and covers, and run saved service calls without opening a browser.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search", text: selectionSearchBinding)
                .textFieldStyle(.roundedBorder)
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
                ScrollView {
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
        .padding(14)
    }

    private var orphanedCustomActionControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unmatched actions")
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
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete unmatched action")
                    .accessibilityLabel("Delete unmatched action \(action.title)")
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
        VStack(alignment: .leading, spacing: 6) {
            selectionDragDrop(
                HStack(alignment: .firstTextBaseline) {
                    Text(room.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
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
                },
                item: .room(room.id)
            )
            ForEach(Array(room.entities.enumerated()), id: \.element.entity.id.rawValue) { index, selectable in
                selectionDragDrop(
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Toggle(
                                selectable.entity.name,
                                isOn: selectionBinding(for: selectable.entity.id)
                            )
                            .toggleStyle(.checkbox)
                            .lineLimit(1)
                            Spacer()
                            selectionMoveButtons(
                                up: {
                                    model.moveEntity(selectable.entity.id, direction: .up)
                                },
                                down: {
                                    model.moveEntity(selectable.entity.id, direction: .down)
                                },
                                upLabel: "Move \(selectable.entity.name) up",
                                downLabel: "Move \(selectable.entity.name) down",
                                canMoveUp: canReorderSelection && index > room.entities.startIndex,
                                canMoveDown: canReorderSelection && index < room.entities.index(before: room.entities.endIndex)
                            )
                        }
                        menuBarControls(for: selectable.entity)
                        customActionControls(for: selectable.entity)
                    },
                    item: .entity(selectable.entity.id)
                )
            }
        }
    }

    private func menuBarControls(for entity: DiscoveredEntity) -> some View {
        let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Menu bar", isOn: menuBarVisibilityBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .accessibilityLabel("Show \(entity.name) in menu bar")
                if isPromoted {
                    menuBarMoveButtons(for: entity)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPromoted {
                HStack(spacing: 10) {
                    Text("Style")
                        .foregroundStyle(.secondary)
                    Picker("Style", selection: menuBarStyleBinding(for: entity.id)) {
                        ForEach(MenuBarDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) menu bar style")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Toggle("Label", isOn: menuBarLabelBinding(for: entity.id))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) label in menu bar")
                    Toggle("Unit", isOn: menuBarUnitBinding(for: entity.id))
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
                menuBarThresholdControls(for: entity, configuration: configuration)
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    private func customActionControls(for entity: DiscoveredEntity) -> some View {
        let actions = model.customActions(for: entity)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Actions")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addCustomAction(for: entity)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add action")
                .accessibilityLabel("Add action for \(entity.name)")
            }
            ForEach(Array(actions.enumerated()), id: \.element.id.rawValue) { index, action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Title", text: customActionTitleBinding(for: action.id))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(entity.name) action title")
                        Toggle("Confirm", isOn: customActionConfirmationBinding(for: action.id))
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("\(action.title) confirmation")
                        customActionMoveButtons(
                            for: action,
                            entityName: entity.name,
                            canMoveUp: canReorderSelection && index > actions.startIndex,
                            canMoveDown: canReorderSelection && index < actions.index(before: actions.endIndex)
                        )
                        Button {
                            model.removeCustomAction(action.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Delete action")
                        .accessibilityLabel("Delete \(action.title)")
                    }
                    customActionServiceSelector(action)
                    TextField("Target entity", text: customActionTargetBinding(for: action.id))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(action.title) target entity")
                    customActionServiceDataControls(action)
                }
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    @ViewBuilder
    private func customActionServiceSelector(_ action: EntityCustomAction) -> some View {
        if model.snapshot.serviceMetadata.isEmpty {
            HStack(spacing: 6) {
                TextField("Domain", text: customActionDomainBinding(for: action.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(action.title) domain")
                TextField("Service", text: customActionServiceBinding(for: action.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(action.title) service")
            }
        } else {
            HStack(spacing: 6) {
                Picker("Domain", selection: customActionMetadataDomainBinding(for: action.id)) {
                    if !metadataDomains.contains(action.action.domain) {
                        Text(action.action.domain).tag(action.action.domain)
                    }
                    ForEach(metadataDomains, id: \.self) { domain in
                        Text(domain).tag(domain)
                    }
                }
                .frame(width: 132)
                .accessibilityLabel("\(action.title) domain")
                Picker("Service", selection: customActionMetadataServiceBinding(for: action.id)) {
                    let services = metadataServices(for: action.action.domain)
                    if !services.contains(where: { $0.service == action.action.service }) {
                        Text(action.action.service).tag(action.action.service)
                    }
                    ForEach(services, id: \.service) { metadata in
                        Text(metadata.service).tag(metadata.service)
                    }
                }
                .frame(width: 132)
                .accessibilityLabel("\(action.title) service")
            }
        }
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
            .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel("Move \(action.title) later for \(entityName)")
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func addCustomAction(for entity: DiscoveredEntity) {
        let action = EntityCustomAction(
            id: nextCustomActionID(for: entity.id),
            entityID: entity.id,
            title: "Update",
            action: ActionSpec(domain: "homeassistant", service: "update_entity", targetEntityID: entity.id)
        )
        model.setCustomAction(action)
    }

    private func customActionServiceDataControls(_ action: EntityCustomAction) -> some View {
        let keys = action.action.serviceData.keys.sorted()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Service data")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addCustomActionServiceDataValue(action.id)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add service data")
                .accessibilityLabel("Add service data for \(action.title)")
            }
            ForEach(keys, id: \.self) { key in
                customActionServiceDataObjectEntry(action, parentPath: [], key: key, nesting: 0)
            }
        }
    }

    private func customActionServiceDataObjectEntry(
        _ action: EntityCustomAction,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        key: String,
        nesting: Int
    ) -> AnyView {
        let path = parentPath + [.key(key)]
        let value = customActionServiceDataValue(for: action.id, path: path) ?? .null
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Key", text: customActionServiceDataKeyBinding(for: action.id, parentPath: parentPath, key: key))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 92, idealWidth: 118)
                        .accessibilityLabel("\(action.title) service data key")
                    customActionServiceDataTypePicker(action, path: path, value: value)
                    customActionServiceDataInlineValueField(action, path: path, value: value)
                    Button {
                        model.removeCustomActionServiceDataValue(action.id, path: path)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete service data")
                    .accessibilityLabel("Delete \(key) from \(action.title)")
                }
                .padding(.leading, CGFloat(nesting) * 12)
                customActionNestedServiceDataControls(action, path: path, value: value, nesting: nesting)
            }
        )
    }

    private func customActionServiceDataArrayEntry(
        _ action: EntityCustomAction,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        index: Int,
        count: Int,
        nesting: Int
    ) -> AnyView {
        let path = parentPath + [.index(index)]
        let value = customActionServiceDataValue(for: action.id, path: path) ?? .null
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("#\(index + 1)")
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    customActionServiceDataTypePicker(action, path: path, value: value)
                    customActionServiceDataInlineValueField(action, path: path, value: value)
                    Button {
                        model.moveCustomActionServiceDataArrayValue(action.id, path: path, direction: .up)
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(index == 0)
                    .help("Move item up")
                    .accessibilityLabel("Move item \(index + 1) up in \(action.title)")
                    Button {
                        model.moveCustomActionServiceDataArrayValue(action.id, path: path, direction: .down)
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(index >= count - 1)
                    .help("Move item down")
                    .accessibilityLabel("Move item \(index + 1) down in \(action.title)")
                    Button {
                        model.removeCustomActionServiceDataValue(action.id, path: path)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete list item")
                    .accessibilityLabel("Delete item \(index + 1) from \(action.title)")
                }
                .padding(.leading, CGFloat(nesting) * 12)
                customActionNestedServiceDataControls(action, path: path, value: value, nesting: nesting)
            }
        )
    }

    private func customActionServiceDataTypePicker(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> some View {
        Picker("Type", selection: customActionServiceDataTypeBinding(for: action.id, path: path)) {
            Text("Text").tag(PerchHACustomActionServiceDataValueKind.string)
            Text("Number").tag(PerchHACustomActionServiceDataValueKind.number)
            Text("Bool").tag(PerchHACustomActionServiceDataValueKind.bool)
            Text("Object").tag(PerchHACustomActionServiceDataValueKind.object)
            Text("List").tag(PerchHACustomActionServiceDataValueKind.array)
        }
        .labelsHidden()
        .frame(width: CustomActionEditorLayout.serviceDataTypePickerWidth)
        .disabled(model.isSensitiveServiceDataPath(path))
        .accessibilityLabel("\(action.title) service data type")
    }

    @ViewBuilder
    private func customActionServiceDataInlineValueField(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> some View {
        if value.isInlineEditable {
            if model.isSensitiveServiceDataPath(path) {
                SecureField(
                    customActionProtectedValuePlaceholder(for: action.id, path: path),
                    text: customActionProtectedValueBinding(for: action.id, path: path)
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth)
                .layoutPriority(1)
                .accessibilityLabel("\(action.title) protected service data value")
            } else {
                TextField("Value", text: customActionServiceDataValueBinding(for: action.id, path: path))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth)
                    .layoutPriority(1)
                    .accessibilityLabel("\(action.title) service data value")
            }
        } else {
            Text(value.editorText)
                .foregroundStyle(.secondary)
                .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth, maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(action.title) service data nested value")
        }
    }

    private func customActionNestedServiceDataControls(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue,
        nesting: Int
    ) -> AnyView {
        switch value {
        case let .object(values):
            let keys = values.keys.sorted()
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(keys, id: \.self) { childKey in
                        customActionServiceDataObjectEntry(action, parentPath: path, key: childKey, nesting: nesting + 1)
                    }
                    Button {
                        addCustomActionObjectServiceDataValue(action.id, parentPath: path)
                    } label: {
                        Label("Add field", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.leading, CGFloat(nesting + 1) * 12)
                    .accessibilityLabel("Add nested service data field for \(action.title)")
                }
            )
        case let .array(values):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(values.indices), id: \.self) { index in
                        customActionServiceDataArrayEntry(
                            action,
                            parentPath: path,
                            index: index,
                            count: values.count,
                            nesting: nesting + 1
                        )
                    }
                    Button {
                        model.appendCustomActionServiceDataArrayValue(action.id, path: path, value: .string(""))
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.leading, CGFloat(nesting + 1) * 12)
                    .accessibilityLabel("Add list item for \(action.title)")
                }
            )
        case .string, .protectedString, .number, .bool, .null:
            return AnyView(EmptyView())
        }
    }

    private func addCustomActionServiceDataValue(_ id: CustomActionID) {
        addCustomActionObjectServiceDataValue(id, parentPath: [])
    }

    private func addCustomActionObjectServiceDataValue(
        _ id: CustomActionID,
        parentPath: [PerchHACustomActionServiceDataPathComponent]
    ) {
        guard let action = model.customAction(id: id) else {
            return
        }
        let values: [String: ActionValue]
        if parentPath.isEmpty {
            values = action.action.serviceData
        } else if case let .object(nestedValues) = customActionServiceDataValue(for: id, path: parentPath) {
            values = nestedValues
        } else {
            return
        }
        var index = 1
        var key = "value\(index)"
        while values[key] != nil {
            index += 1
            key = "value\(index)"
        }
        model.setCustomActionServiceDataValue(id, path: parentPath + [.key(key)], value: .string(""))
    }

    private var metadataDomains: [String] {
        Array(Set(model.snapshot.serviceMetadata.map(\.domain))).sorted()
    }

    private func metadataServices(for domain: String) -> [HAServiceMetadata] {
        model.snapshot.serviceMetadata
            .filter { $0.domain == domain }
            .sorted { lhs, rhs in lhs.service < rhs.service }
    }

    private func customActionMetadataDomainBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.domain ?? ""
            },
            set: { domain in
                guard let action = model.customAction(id: id) else {
                    return
                }
                let service = metadataServices(for: domain).first?.service ?? action.action.service
                model.setCustomActionService(id, domain: domain, service: service)
            }
        )
    }

    private func customActionMetadataServiceBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.service ?? ""
            },
            set: { service in
                guard let action = model.customAction(id: id) else {
                    return
                }
                model.setCustomActionService(id, domain: action.action.domain, service: service)
            }
        )
    }

    private func customActionServiceDataKeyBinding(
        for id: CustomActionID,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        key: String
    ) -> Binding<String> {
        Binding(
            get: {
                key
            },
            set: { newKey in
                model.renameCustomActionServiceDataKey(id, parentPath: parentPath, from: key, to: newKey)
            }
        )
    }

    private func customActionServiceDataTypeBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<PerchHACustomActionServiceDataValueKind> {
        Binding(
            get: {
                customActionServiceDataValue(for: id, path: path)?.editorType ?? .string
            },
            set: { type in
                model.setCustomActionServiceDataType(id, path: path, kind: type)
            }
        )
    }

    private func customActionServiceDataValueBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<String> {
        Binding(
            get: {
                customActionServiceDataValue(for: id, path: path)?.editorText ?? ""
            },
            set: { text in
                let type = customActionServiceDataValue(for: id, path: path)?.editorType ?? .string
                model.setCustomActionServiceDataText(id, path: path, text: text, kind: type)
            }
        )
    }

    private func customActionProtectedValueBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<String> {
        Binding(
            get: {
                model.protectedValueDraft(for: id, path: path)
            },
            set: { text in
                model.setCustomActionServiceDataText(id, path: path, text: text, kind: .string)
            }
        )
    }

    private func customActionProtectedValuePlaceholder(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> String {
        if case .protectedString = customActionServiceDataValue(for: id, path: path) {
            return "Stored in Keychain"
        }
        return "Value"
    }

    private func customActionServiceDataValue(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> ActionValue? {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return nil
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var value = model.customAction(id: id)?.action.serviceData[trimmedKey] else {
            return nil
        }
        for component in path.dropFirst() {
            switch (component, value) {
            case let (.key(key), .object(values)):
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let nextValue = values[trimmedKey] else {
                    return nil
                }
                value = nextValue
            case let (.index(index), .array(values)):
                guard values.indices.contains(index) else {
                    return nil
                }
                value = values[index]
            case (.key, .string),
                 (.key, .protectedString),
                 (.key, .number),
                 (.key, .bool),
                 (.key, .array),
                 (.key, .null),
                 (.index, .string),
                 (.index, .protectedString),
                 (.index, .number),
                 (.index, .bool),
                 (.index, .object),
                 (.index, .null):
                return nil
            }
        }
        return value
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

    private func customActionDomainBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.domain ?? ""
            },
            set: { domain in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: domain,
                            service: action.action.service,
                            targetEntityID: action.action.targetEntityID,
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionServiceBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.service ?? ""
            },
            set: { service in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: action.action.domain,
                            service: service,
                            targetEntityID: action.action.targetEntityID,
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionTargetBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.targetEntityID?.rawValue ?? ""
            },
            set: { targetEntityID in
                updateCustomAction(id) { action in
                    let trimmedTarget = targetEntityID.trimmingCharacters(in: .whitespacesAndNewlines)
                    return EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: action.action.domain,
                            service: action.action.service,
                            targetEntityID: trimmedTarget.isEmpty ? nil : EntityID(trimmedTarget),
                            serviceData: action.action.serviceData
                        ),
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
                Toggle("Warn", isOn: menuBarWarningEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) warning threshold")
                if configuration.thresholds.warning != nil {
                    Picker("Warn", selection: menuBarWarningDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) warning threshold direction")
                    Stepper(
                        "Warn \(menuBarNumberLabel(configuration.thresholds.warning?.value))",
                        value: menuBarWarningValueBinding(for: entity.id),
                        in: -100_000...100_000,
                        step: 1
                    )
                    .accessibilityLabel("\(entity.name) warning threshold value")
                }
            }
            HStack(spacing: 8) {
                Toggle("Crit", isOn: menuBarCriticalEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) critical threshold")
                if configuration.thresholds.critical != nil {
                    Picker("Crit", selection: menuBarCriticalDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) critical threshold direction")
                    Stepper(
                        "Crit \(menuBarNumberLabel(configuration.thresholds.critical?.value))",
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
            .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
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
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel(upLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
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

    private var selfSignedCertificateBinding: Binding<Bool> {
        Binding(
            get: {
                model.snapshot.connectionForm.allowsSelfSignedCertificates
            },
            set: { value in
                model.updateConnectionForm(allowsSelfSignedCertificates: value)
            }
        )
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
