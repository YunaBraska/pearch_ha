import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PearchHACore
import PearchHASupport

/// Connection form field stack shared by the menu-bar panel's first-run view and
/// the Settings window's Connection tab.
///
/// The shared fields cover the Home Assistant URL, fallback URL, access token,
/// the failure/progress banners, the sign-in/connect buttons, and an explicit
/// self-signed certificate opt-in scoped to the entered HTTPS hosts.
/// Certificate validation stays strict unless the user opts in.
struct PearchHAConnectionFormFields: View {
    let model: PearchHAPanelModel
    let snapshot: PearchHAPanelSnapshot
    let oauthSignInState: PearchHAOAuthSignInState

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
                tokenAccessDivider
            }

            VStack(alignment: .leading, spacing: 6) {
                tokenAccessFields
                Button(tokenAccessPresentation.editableButtonTitle) {
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
                PearchHANativeTextField(
                    placeholder: "Home Assistant URL",
                    text: urlBinding,
                    contentType: {
                        if #available(macOS 14.0, *) {
                            return .URL
                        }
                        return nil
                    }(),
                    normalizeOnCommit: PearchHAConnectionForm.normalizedHomeAssistantURLString
                )
            }

            ForEach(Array(snapshot.connectionForm.addresses.enumerated()), id: \.element.id) { index, address in
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
                    get: { snapshot.connectionForm.allowsSelfSignedCertificates },
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

    private func alternativeAddressRow(_ address: PearchHAConnectionAddressField, index: Int) -> some View {
        let count = snapshot.connectionForm.addresses.count
        let invalid = !address.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && address.validURL == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PearchHANativeTextField(
                    placeholder: "Label (optional)",
                    text: labelBinding(id: address.id),
                    contentType: nil,
                    normalizeOnCommit: { $0 }
                )
                .frame(width: 130)
                PearchHANativeTextField(
                    placeholder: "Alternative URL",
                    text: addressURLBinding(id: address.id),
                    contentType: {
                        if #available(macOS 14.0, *) {
                            return .URL
                        }
                        return nil
                    }(),
                    normalizeOnCommit: PearchHAConnectionForm.normalizedHomeAssistantURLString
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
        if snapshot.showsConnectedContent {
            return true
        }
        switch snapshot.connectionState {
        case .connected, .reconnecting:
            return true
        case .connecting, .disconnected, .failed:
            return false
        }
    }

    /// The host shown in the connected state, derived from the real stored
    /// connection URL (not a blanked editing binding).
    private var connectedHost: String? {
        let urlString = snapshot.connectionForm.urlString
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

            tokenAccessFields

            HStack(spacing: 8) {
                Button(tokenAccessPresentation.connectedButtonTitle) {
                    model.applyConnectionEdits()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isConnectionBusy || !model.canApplyConnectionEdits)
                .help(tokenAccessPresentation.connectedActionHelp)

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

    private var tokenAccessDivider: some View {
        Group {
            line
            Text("or use an access token")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
    }

    private var tokenAccessFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            PearchHANativeSecureField(
                placeholder: tokenAccessPresentation.fieldPlaceholder,
                text: tokenBinding,
                contentType: .password
            )
            if let savedTokenGuidance = tokenAccessPresentation.savedTokenGuidance {
                Text(savedTokenGuidance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(tokenAccessPresentation.tokenCreationGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Where to find a token: Home Assistant profile, Security, Long-lived access tokens.")
        }
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        if let failureDescription = snapshot.failureDescription {
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
        PearchHAErrorState(
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
        if case let .failed(message) = oauthSignInState {
            return message
        }
        return nil
    }

    private var oauthSignInButtonTitle: String {
        oauthSignInState == .signingIn ? "Signing in..." : "Sign in"
    }

    private var connectionProgressMessage: String? {
        if oauthSignInState == .signingIn {
            return "Signing in"
        }
        if snapshot.connectionState == .connecting {
            return "Connecting to Home Assistant"
        }
        return nil
    }

    private var isConnectionBusy: Bool {
        snapshot.connectionState == .connecting || oauthSignInState == .signingIn
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { snapshot.connectionForm.urlString },
            set: { value in
                model.updateConnectionForm(urlString: value)
            }
        )
    }

    private func labelBinding(id: PearchHAConnectionAddressField.ID) -> Binding<String> {
        Binding(
            get: { snapshot.connectionForm.addresses.first { $0.id == id }?.label ?? "" },
            set: { value in
                model.updateConnectionAddress(id: id, label: value)
            }
        )
    }

    private func addressURLBinding(id: PearchHAConnectionAddressField.ID) -> Binding<String> {
        Binding(
            get: { snapshot.connectionForm.addresses.first { $0.id == id }?.urlString ?? "" },
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

    private var tokenAccessPresentation: PearchHAConnectionTokenAccessPresentation {
        PearchHAConnectionTokenAccessPresentation(
            usesStoredToken: snapshot.connectionForm.usesStoredAuthSession,
            tokenDraft: model.tokenInputForView
        )
    }
}
