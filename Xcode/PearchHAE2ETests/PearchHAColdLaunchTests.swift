import AppKit
import ApplicationServices
import XCTest
import os

@MainActor
final class PearchHAColdLaunchTests: XCTestCase {
    private struct Activation: Sendable {
        let timestamp: TimeInterval
        let bundleIdentifier: String
    }

    func testColdStatusClicksAndKeyboardAcrossIndependentLaunches() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITHUB_ACTIONS"] == "true",
              environment["RUNNER_ENVIRONMENT"] == "github-hosted",
              environment["PEARCHHA_NATIVE_E2E"] == "1" else {
            throw NSError(domain: "PearchHAE2ETests", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Native UI tests require an explicitly enabled GitHub-hosted macOS runner. Local and self-hosted execution is prohibited."])
        }
        continueAfterFailure = false
        let appPath = try XCTUnwrap(environment["PEARCHHA_E2E_APP_PATH"], "The CI script must supply the built production app path")
        let appURL = URL(fileURLWithPath: appPath).standardizedFileURL
        XCTAssertTrue(appPath.hasPrefix("/"))
        XCTAssertEqual(Bundle(url: appURL)?.bundleIdentifier, "dev.pearchha.app")
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "dev.pearchha.app").isEmpty,
                      "The production app must not be prelaunched by XCTest or another process")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PearchHAE2E-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(NSWorkspace.shared.open(directory))
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let finderWindow = finder.windows[directory.lastPathComponent]
        XCTAssertTrue(finderWindow.waitForExistence(timeout: 10), "Finder must show the owned empty test folder")
        var runningApp: NSRunningApplication?
        defer { runningApp?.terminate() }

        for session in 1...2 {
            finder.activate()
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.finder")
            let activations = OSAllocatedUnfairLock(initialState: [Activation]())
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { @Sendable notification in
                let identifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? "unknown"
                activations.withLock { $0.append(Activation(timestamp: ProcessInfo.processInfo.systemUptime, bundleIdentifier: identifier)) }
            }
            defer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.allowsRunningApplicationSubstitution = false
            let launched = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            runningApp = launched
            XCTAssertEqual(launched.bundleURL?.standardizedFileURL, appURL)
            let app = XCUIApplication(url: appURL)
            let root = app.descendants(matching: .any).matching(identifier: "pearchha.menuPopover").firstMatch
            let statusItem = app.statusItems.matching(NSPredicate(format: "label == %@", "PearchHA")).firstMatch
            XCTAssertTrue(statusItem.waitForExistence(timeout: 15), "A clean production launch must expose its fallback status item")
            let coldClick = try statusCoordinate(statusItem, from: finder.menuBars.firstMatch)
            record("Cold session \(session): before first click", app: app, activations: activations)
            XCTAssertFalse(root.exists)
            XCTAssertFalse(launched.isActive, "The cold app must remain inactive until the physical status click")
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.finder")
            XCTAssertFalse(activations.withLock { $0.contains { $0.bundleIdentifier == "dev.pearchha.app" } },
                           "Querying the target must not activate it before the cold click")
            // No PearchHA query or interaction occurs between these assertions and this Finder-owned click.
            coldClick.click()
            try await waitUntil("The first cold status click shows and activates the popover") { launched.isActive && root.exists }
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, launched.processIdentifier)
            assertKeyboardWindow(in: launched)
            record("Cold session \(session): first click opened", app: app, activations: activations)

            // PearchHA is already active. Referencing its visible root cannot mask cold activation.
            try statusCoordinate(statusItem, from: root).click()
            XCTAssertTrue(root.waitForNonExistence(timeout: 5), "The very next native status click closes the popover")
            record("Cold session \(session): first close", app: app, activations: activations)

            finder.activate()
            XCTAssertFalse(launched.isActive)
            try statusCoordinate(statusItem, from: finder.menuBars.firstMatch).click()
            try await waitUntil("One status click reopens from Finder") { launched.isActive && root.exists }
            assertKeyboardWindow(in: launched)
            let finderTitle = finderWindow.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: finderWindow.frame.width / 2, dy: 12))
            finderTitle.click()
            XCTAssertTrue(root.waitForNonExistence(timeout: 5), "An actual Finder title click dismisses the popover")
            XCTAssertFalse(launched.isActive)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, "com.apple.finder")
            record("Cold session \(session): Finder outside dismissal", app: app, activations: activations)

            try statusCoordinate(statusItem, from: finder.menuBars.firstMatch).click()
            try await waitUntil("One click restores the panel after Finder dismissal") { launched.isActive && root.exists }
            assertKeyboardWindow(in: launched)
            root.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
            XCTAssertTrue(root.waitForNonExistence(timeout: 5), "Escape reaches and closes the production popover")
            record("Cold session \(session): Escape dismissal", app: app, activations: activations)

            finder.activate()
            XCTAssertFalse(launched.isActive)
            try statusCoordinate(statusItem, from: finder.menuBars.firstMatch).click()
            try await waitUntil("One click reopens after Escape") { launched.isActive && root.exists }
            assertKeyboardWindow(in: launched)
            root.typeKey(",", modifierFlags: .command)
            let settings = app.windows["PearchHA Settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5), "Cmd+, reaches the production main menu and opens Settings")
            XCTAssertFalse(root.exists, "Settings replaces the outer popover")
            record("Cold session \(session): Cmd+, Settings", app: app, activations: activations)
            settings.typeKey("w", modifierFlags: .command)
            XCTAssertTrue(settings.waitForNonExistence(timeout: 5))

            XCTAssertTrue(launched.terminate())
            try await waitUntil("The process terminates before the next independent launch") { launched.isTerminated }
            runningApp = nil
            XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: "dev.pearchha.app").isEmpty)
        }
        finder.activate()
        finderWindow.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(finderWindow.waitForNonExistence(timeout: 5))
    }

    private func statusCoordinate(_ statusItem: XCUIElement, from reference: XCUIElement) throws -> XCUICoordinate {
        XCTAssertTrue(reference.exists)
        let frame = statusItem.frame
        XCTAssertTrue(frame.width > 0 && frame.height > 0 && !frame.isInfinite && !frame.isNull,
                      "The native status item must have an observed screen frame")
        let origin = reference.coordinate(withNormalizedOffset: .zero)
        let originPoint = origin.screenPoint
        let click = origin.withOffset(CGVector(dx: frame.midX - originPoint.x, dy: frame.midY - originPoint.y))
        XCTAssertEqual(click.screenPoint.x, frame.midX, accuracy: 0.5)
        XCTAssertEqual(click.screenPoint.y, frame.midY, accuracy: 0.5)
        return click
    }

    private func assertKeyboardWindow(in application: NSRunningApplication) {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        XCTAssertEqual(result, .success, "Public accessibility must expose the keyboard-focused window; AX trusted=\(AXIsProcessTrusted())")
        XCTAssertNotNil(focusedWindow, "The cold click must establish keyboard window focus without a test activation")
    }

    private func waitUntil(_ description: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() {
            guard ContinuousClock.now < deadline else {
                XCTFail(description)
                throw NSError(domain: "PearchHAE2ETests", code: 2, userInfo: [NSLocalizedDescriptionKey: description])
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func record(_ title: String, app: XCUIApplication, activations: OSAllocatedUnfairLock<[Activation]>) {
        XCTContext.runActivity(named: title) { activity in
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
            let trace = activations.withLock { values in
                values.map { "\($0.timestamp): \($0.bundleIdentifier)" }.joined(separator: "\n")
            }
            let state = XCTAttachment(string: "frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")\n\(trace)\n\(app.debugDescription)")
            state.lifetime = .keepAlways
            activity.add(state)
        }
    }
}
