#if canImport(XCTest)
import Foundation
import XCTest
import PerchHACore
import PerchHAPersistence

final class PerchHAPersistenceTests: XCTestCase {
    func testConfigLocationDefaults() {
        let location = ConfigLocation()

        XCTAssertEqual(location.applicationSupportDirectoryName, "PerchHA")
        XCTAssertEqual(location.fileName, "config.json")
    }

    func testJSONConfigStoreReturnsEmptyConfigWhenFileIsMissing() throws {
        let store = JSONConfigStore(fileURL: temporaryConfigURL())

        XCTAssertEqual(try store.load(), .empty)
        XCTAssertTrue(try store.load().isEntitySelectionExplicit)
    }

    func testJSONConfigStoreRoundTripsVersionedConfiguration() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            selectedEntityIDs: ["sensor.office_temperature", "switch.office_lamp"],
            menuBarEntityIDs: ["sensor.office_temperature"],
            menuBarItemConfigurations: [
                MenuBarItemConfiguration(
                    entityID: "sensor.office_temperature",
                    style: .battery,
                    showsLabel: true,
                    showsUnit: false,
                    maximumFractionDigits: 2,
                    absoluteTotal: 120,
                    thresholds: ValueThresholds(
                        warning: ValueThreshold(value: 30, direction: .belowOrEqual),
                        critical: ValueThreshold(value: 15, direction: .belowOrEqual)
                    ),
                    defaultHistoryRange: .week
                ),
                MenuBarItemConfiguration(
                    entityID: "sensor.energy_today",
                    style: .bar,
                    totalEntityID: "sensor.energy_budget",
                    defaultHistoryRange: .month,
                    showsEntityIcon: false,
                    customIconName: "flame"
                )
            ],
            customActions: [
                EntityCustomAction(
                    id: "boost-air",
                    entityID: "sensor.office_temperature",
                    title: "Boost air",
                    action: ActionSpec(
                        domain: "script",
                        service: "turn_on",
                        targetEntityID: "script.air_cleaner_boost",
                        serviceData: [
                            "mode": "boost",
                            "duration": 15,
                            "metadata": .object([
                                "source": "perchha",
                                "pinned": true,
                                "steps": .array([
                                    .object([
                                        "service": "fan.set_preset_mode",
                                        "data": .object([
                                            "preset_mode": "boost",
                                            "duration": 15
                                        ])
                                    ])
                                ])
                            ])
                        ]
                    ),
                    requiresConfirmation: true
                )
            ],
            connectionProfile: PerchHAConnectionProfile(
                urlString: "https://homeassistant.local:8123",
                fallbackURLString: "https://fallback.example/ha"
            ),
            roomOrder: ["office", "kitchen"],
            entityOrder: ["switch.office_lamp", "sensor.office_temperature"]
        )

        XCTAssertEqual(try store.save(configuration), configuration)
        XCTAssertEqual(try store.load(), configuration)
    }

    func testJSONConfigStoreDefaultsMissingHistoryRangeToInheritGlobal() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "menuBarItemConfigurations": [
            {
              "entityID": "sensor.office_temperature",
              "style": "battery",
              "showsLabel": true,
              "showsUnit": false,
              "maximumFractionDigits": 2
            }
          ]
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let configuration = try JSONConfigStore(fileURL: url).load()

        // No stored range means "inherit the global Appearance default".
        XCTAssertNil(
            configuration.menuBarDisplayConfiguration
                .itemConfiguration(for: "sensor.office_temperature")
                .defaultHistoryRange
        )
        XCTAssertEqual(configuration.customActionConfiguration, CustomActionConfiguration())
    }

    func testConfigurationDefaultsDisplayPreferences() {
        let configuration = PerchHAConfiguration.empty

        XCTAssertEqual(configuration.menuBarAppearance, .iconAndText)
        XCTAssertFalse(configuration.stableMenuBarWidth)
        XCTAssertEqual(configuration.themeMode, .system)
        XCTAssertEqual(configuration.accentColor, .homeAssistantBlue)
        XCTAssertEqual(configuration.dashboardRowDensity, .comfortable)
        XCTAssertEqual(configuration.dashboardDefaultHistoryRange, .day)
        XCTAssertTrue(configuration.dashboardShowsFooterTimestamp)
        XCTAssertTrue(configuration.dashboardHiddenModuleIDs.isEmpty)
        XCTAssertEqual(configuration.dashboardRoomRowLimit, 6)
    }

    func testJSONConfigStoreRoundTripsDisplayPreferences() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            menuBarAppearance: .iconOnly,
            stableMenuBarWidth: true,
            themeMode: .dark,
            accentColor: PerchHAAccentColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.9),
            dashboardRowDensity: .compact,
            dashboardDefaultHistoryRange: .week,
            dashboardShowsFooterTimestamp: false,
            dashboardHiddenModuleIDs: ["room.office", "room.kitchen"],
            dashboardRoomRowLimit: -1
        )

        try store.save(configuration)

        XCTAssertEqual(try store.load(), configuration)
    }

    func testConfigurationDisplayPreferencesBridgesDashboardFields() {
        let configuration = PerchHAConfiguration(
            dashboardRowDensity: .compact,
            dashboardDefaultHistoryRange: .week,
            dashboardShowsFooterTimestamp: false,
            dashboardHiddenModuleIDs: ["room.office"],
            dashboardRoomRowLimit: 12
        )

        let preferences = configuration.displayPreferences

        XCTAssertEqual(preferences.dashboardRowDensity, .compact)
        XCTAssertEqual(preferences.defaultHistoryRange, .week)
        XCTAssertFalse(preferences.showsFooterTimestamp)
        XCTAssertEqual(preferences.hiddenModuleIDs, ["room.office"])
        XCTAssertEqual(preferences.dashboardRoomRowLimit, 12)
    }

    func testConfigurationApplyingDisplayPreferencesReplacesOnlyDisplayFields() {
        let base = PerchHAConfiguration(
            selectedEntityIDs: ["sensor.office_temperature"],
            menuBarEntityIDs: ["sensor.office_temperature"]
        )
        let preferences = PerchHADisplayPreferences.defaults
            .with(dashboardRowDensity: .compact)
            .with(defaultHistoryRange: .week)
            .with(showsFooterTimestamp: false)
            .with(hiddenModuleIDs: ["room.office"])
            .with(dashboardRoomRowLimit: -3)

        let applied = base.applying(displayPreferences: preferences)

        // Display fields take the new values.
        XCTAssertEqual(applied.dashboardRowDensity, .compact)
        XCTAssertEqual(applied.dashboardDefaultHistoryRange, .week)
        XCTAssertFalse(applied.dashboardShowsFooterTimestamp)
        XCTAssertEqual(applied.dashboardHiddenModuleIDs, ["room.office"])
        XCTAssertEqual(applied.dashboardRoomRowLimit, -3)
        // Selection/menu-bar state is preserved untouched.
        XCTAssertEqual(applied.selectedEntityIDs, ["sensor.office_temperature"])
        XCTAssertEqual(applied.menuBarEntityIDs, ["sensor.office_temperature"])
    }

    func testJSONConfigStoreDefaultsMissingDisplayPreferencesForBackCompat() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "selectedEntityIDs": ["sensor.office_temperature"]
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let configuration = try JSONConfigStore(fileURL: url).load()

        XCTAssertEqual(configuration.menuBarAppearance, .iconAndText)
        XCTAssertFalse(configuration.stableMenuBarWidth)
        XCTAssertEqual(configuration.themeMode, .system)
        XCTAssertEqual(configuration.accentColor, .homeAssistantBlue)
        // New dashboard display fields decode to their shipped defaults when a
        // pre-existing config file omits them.
        XCTAssertEqual(configuration.dashboardRowDensity, .comfortable)
        XCTAssertEqual(configuration.dashboardDefaultHistoryRange, .day)
        XCTAssertTrue(configuration.dashboardShowsFooterTimestamp)
        XCTAssertTrue(configuration.dashboardHiddenModuleIDs.isEmpty)
        // Absent summary-metric selection decodes to empty, i.e. automatic.
        XCTAssertTrue(configuration.dashboardSummaryMetricEntityIDs.isEmpty)
        // Absent room-row limit decodes to the shipped default.
        XCTAssertEqual(configuration.dashboardRoomRowLimit, 6)
    }

    func testConfigurationDefaultsSummaryMetricEntityIDsToEmpty() {
        XCTAssertTrue(PerchHAConfiguration.empty.dashboardSummaryMetricEntityIDs.isEmpty)
        XCTAssertTrue(PerchHAConfiguration.empty.displayPreferences.summaryMetricEntityIDs.isEmpty)
    }

    func testJSONConfigStoreRoundTripsSummaryMetricEntityIDs() throws {
        let url = temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            dashboardSummaryMetricEntityIDs: ["sensor.office_temperature", "sensor.office_humidity"]
        )

        try store.save(configuration)

        let reloaded = try store.load()
        XCTAssertEqual(reloaded, configuration)
        XCTAssertEqual(
            reloaded.dashboardSummaryMetricEntityIDs,
            ["sensor.office_temperature", "sensor.office_humidity"]
        )
        XCTAssertEqual(
            reloaded.displayPreferences.summaryMetricEntityIDs,
            ["sensor.office_temperature", "sensor.office_humidity"]
        )
    }

    func testSummaryMetricEntityIDsCappedAtThreeOnStore() throws {
        let url = temporaryConfigURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            dashboardSummaryMetricEntityIDs: ["sensor.a", "sensor.b", "sensor.c", "sensor.d"]
        )

        // The init itself caps the selection to three ordered entries.
        XCTAssertEqual(
            configuration.dashboardSummaryMetricEntityIDs,
            ["sensor.a", "sensor.b", "sensor.c"]
        )

        try store.save(configuration)
        XCTAssertEqual(try store.load().dashboardSummaryMetricEntityIDs, ["sensor.a", "sensor.b", "sensor.c"])
    }

    func testApplyingDisplayPreferencesCarriesSummaryMetricEntityIDs() {
        let base = PerchHAConfiguration(selectedEntityIDs: ["sensor.office_temperature"])
        let preferences = PerchHADisplayPreferences.defaults
            .with(summaryMetricEntityIDs: ["sensor.office_humidity"])

        let applied = base.applying(displayPreferences: preferences)

        XCTAssertEqual(applied.dashboardSummaryMetricEntityIDs, ["sensor.office_humidity"])
        // Selection state is preserved untouched.
        XCTAssertEqual(applied.selectedEntityIDs, ["sensor.office_temperature"])
        // And round-trips back to the bundle.
        XCTAssertEqual(applied.displayPreferences.summaryMetricEntityIDs, ["sensor.office_humidity"])
    }

    func testDisplayPreferencesCapsAndDeduplicatesSummaryMetricEntityIDs() {
        let prefs = PerchHADisplayPreferences.defaults
            .with(summaryMetricEntityIDs: ["sensor.a", "sensor.a", "sensor.b", "sensor.c", "sensor.d"])

        XCTAssertEqual(prefs.summaryMetricEntityIDs, ["sensor.a", "sensor.b", "sensor.c"])
    }

    func testAccentColorClampsChannelsIntoUnitRange() {
        let accent = PerchHAAccentColor(red: -0.5, green: 2, blue: 0.3, alpha: 5)

        XCTAssertEqual(accent.red, 0)
        XCTAssertEqual(accent.green, 1)
        XCTAssertEqual(accent.blue, 0.3)
        XCTAssertEqual(accent.alpha, 1)
    }

    func testAccentColorMatchesNamedSwatch() {
        XCTAssertEqual(PerchHAAccentColor.homeAssistantBlue.matchingSwatchID, "ha-blue")
        XCTAssertNil(PerchHAAccentColor(red: 0.123, green: 0.456, blue: 0.789).matchingSwatchID)
    }

    func testDisplayPreferencesWithReplacesSingleField() {
        let base = PerchHADisplayPreferences.defaults

        XCTAssertEqual(base.with(menuBarAppearance: .textOnly).menuBarAppearance, .textOnly)
        XCTAssertTrue(base.with(stableMenuBarWidth: true).stableMenuBarWidth)
        XCTAssertEqual(base.with(themeMode: .light).themeMode, .light)
        XCTAssertEqual(
            base.with(accentColor: .homeAssistantBlue).accentColor,
            .homeAssistantBlue
        )
        XCTAssertEqual(base.with(dashboardRowDensity: .compact).dashboardRowDensity, .compact)
        XCTAssertEqual(base.with(defaultHistoryRange: .week).defaultHistoryRange, .week)
        XCTAssertFalse(base.with(showsFooterTimestamp: false).showsFooterTimestamp)
        XCTAssertEqual(base.with(hiddenModuleIDs: ["room.office"]).hiddenModuleIDs, ["room.office"])
        // Replacing one field leaves the rest at their defaults.
        XCTAssertEqual(base.with(themeMode: .light).menuBarAppearance, .iconAndText)
        XCTAssertEqual(base.with(dashboardRowDensity: .compact).defaultHistoryRange, .day)
        XCTAssertTrue(base.with(hiddenModuleIDs: ["room.office"]).showsFooterTimestamp)
    }

    func testJSONConfigStoreRejectsMalformedCustomActionsOnLoad() throws {
        let cases: [(name: String, json: String, expectedMessage: String)] = [
            (
                "blank title",
                """
                {
                  "schemaVersion": 1,
                  "customActions": [
                    {
                      "id": "bad-action",
                      "entityID": "sensor.office_temperature",
                      "title": " ",
                      "action": {
                        "domain": "script",
                        "service": "turn_on",
                        "targetEntityID": "script.air_cleaner_boost",
                        "serviceData": {}
                      },
                      "requiresConfirmation": false
                    }
                  ]
                }
                """,
                "custom action bad-action is incomplete"
            ),
            (
                "duplicate id",
                """
                {
                  "schemaVersion": 1,
                  "customActions": [
                    {
                      "id": "boost-air",
                      "entityID": "sensor.office_temperature",
                      "title": "Boost air",
                      "action": {
                        "domain": "script",
                        "service": "turn_on",
                        "targetEntityID": "script.air_cleaner_boost",
                        "serviceData": {}
                      },
                      "requiresConfirmation": false
                    },
                    {
                      "id": "boost-air",
                      "entityID": "sensor.office_humidity",
                      "title": "Boost humidity",
                      "action": {
                        "domain": "script",
                        "service": "turn_on",
                        "targetEntityID": "script.humidity_boost",
                        "serviceData": {}
                      },
                      "requiresConfirmation": false
                    }
                  ]
                }
                """,
                "custom action ID boost-air is duplicated"
            ),
            (
                "protected service data",
                """
                {
                  "schemaVersion": 1,
                  "customActions": [
                    {
                      "id": "arm-alarm",
                      "entityID": "sensor.office_temperature",
                      "title": "Arm alarm",
                      "action": {
                        "domain": "alarm_control_panel",
                        "service": "alarm_arm_home",
                        "targetEntityID": "alarm_control_panel.home",
                        "serviceData": {
                          "alarm": {
                            "pin": "1234"
                          }
                        }
                      },
                      "requiresConfirmation": true
                    }
                  ]
                }
                """,
                "protected service data key serviceData.alarm.pin"
            ),
            (
                "protected service data inside array",
                """
                {
                  "schemaVersion": 1,
                  "customActions": [
                    {
                      "id": "arm-alarm",
                      "entityID": "sensor.office_temperature",
                      "title": "Arm alarm",
                      "action": {
                        "domain": "alarm_control_panel",
                        "service": "alarm_arm_home",
                        "targetEntityID": "alarm_control_panel.home",
                        "serviceData": {
                          "steps": [
                            {
                              "pin": "1234"
                            }
                          ]
                        }
                      },
                      "requiresConfirmation": true
                    }
                  ]
                }
                """,
                "protected service data key serviceData.steps[0].pin"
            )
        ]

        for testCase in cases {
            let url = temporaryConfigURL()
            defer {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(testCase.json.utf8).write(to: url)

            XCTAssertThrowsError(try JSONConfigStore(fileURL: url).load(), testCase.name) { error in
                guard case let .malformedConfig(_, message) = error as? ConfigStoreError else {
                    XCTFail("expected malformed config for \(testCase.name), got \(error)")
                    return
                }
                XCTAssertTrue(message.contains(testCase.expectedMessage), testCase.name)
            }
        }
    }

    func testJSONConfigStoreRoundTripsProtectedCustomActionReferencesWithoutSecretBytes() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            customActions: [
                EntityCustomAction(
                    id: "arm-alarm",
                    entityID: "sensor.office_temperature",
                    title: "Arm alarm",
                    action: ActionSpec(
                        domain: "alarm_control_panel",
                        service: "alarm_arm_home",
                        targetEntityID: "alarm_control_panel.home",
                        serviceData: ["alarm_code": .protectedString("protected-ref")]
                    ),
                    requiresConfirmation: true
                )
            ]
        )

        XCTAssertEqual(try store.save(configuration), configuration)
        XCTAssertEqual(try store.load(), configuration)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains(#""$perchha" : "protected_string""#))
        XCTAssertTrue(text.contains(#""reference" : "protected-ref""#))
        XCTAssertFalse(text.contains("1234"))
    }

    func testJSONConfigStoreRejectsUnsupportedSchemaWithoutOverwritingExistingConfig() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let valid = PerchHAConfiguration(selectedEntityIDs: ["sensor.office_temperature"])
        let unsupported = PerchHAConfiguration(schemaVersion: 999, selectedEntityIDs: ["sensor.bad"])

        _ = try store.save(valid)

        XCTAssertThrowsError(try store.save(unsupported)) { error in
            XCTAssertEqual(error as? ConfigStoreError, .unsupportedSchemaVersion(999))
        }
        XCTAssertEqual(try store.load(), valid)
    }

    func testConfigStoreWritesAtomicallyEnoughToLeaveOneReadableJSONFile() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let first = PerchHAConfiguration(selectedEntityIDs: ["sensor.first"])
        let second = PerchHAConfiguration(selectedEntityIDs: ["sensor.second"], roomOrder: ["lab"])

        _ = try store.save(first)
        _ = try store.save(second)

        XCTAssertEqual(try store.load(), second)
        let data = try Data(contentsOf: url)
        XCTAssertNoThrow(try JSONDecoder().decode(PerchHAConfiguration.self, from: data))
        XCTAssertFalse(String(data: data, encoding: .utf8)?.contains("sensor.first") ?? true)
    }

    func test_t_select_reorder_persist() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: url)
        let configuration = PerchHAConfiguration(
            selectedEntityIDs: ["sensor.office_humidity", "switch.kitchen_light"],
            roomOrder: ["kitchen", "office"],
            entityOrder: ["switch.kitchen_light", "sensor.office_humidity"],
            isEntitySelectionExplicit: true
        )
        let rooms = [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.office_humidity",
                        name: "Office humidity",
                        state: "44",
                        unit: "%",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            ),
            Room(
                id: "kitchen",
                name: "Kitchen",
                entities: [
                    DiscoveredEntity(
                        id: "switch.kitchen_light",
                        name: "Kitchen light",
                        state: "off",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]

        _ = try store.save(configuration)
        let loaded = try store.load()
        let selectedRooms = EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: loaded.selectionConfiguration
        )

        XCTAssertEqual(loaded, configuration)
        XCTAssertEqual(selectedRooms.map(\.id.rawValue), ["kitchen", "office"])
        XCTAssertEqual(
            selectedRooms.flatMap(\.entities).map(\.id.rawValue),
            ["switch.kitchen_light", "sensor.office_humidity"]
        )
    }

    func test_t_secret_storage_and_redaction() throws {
        let store = KeychainSecretStore(service: "dev.perchha.tests.\(UUID().uuidString)")
        defer {
            _ = try? store.delete(.accessToken)
            _ = try? store.delete(.refreshToken)
            _ = try? store.delete(.oauthClientID)
        }

        XCTAssertEqual(try store.delete(.accessToken), .notFound)
        XCTAssertEqual(try store.save("secret-token", for: .accessToken), .created)
        XCTAssertEqual(try store.read(.accessToken), "secret-token")
        XCTAssertEqual(try store.save("rotated-token", for: .accessToken), .updated)
        XCTAssertEqual(try store.read(.accessToken), "rotated-token")
        XCTAssertEqual(try store.save("refresh-secret", for: .refreshToken), .created)
        XCTAssertEqual(try store.read(.refreshToken), "refresh-secret")

        XCTAssertThrowsError(try store.save("", for: .accessToken)) { error in
            XCTAssertEqual(error as? SecretStoreError, .emptySecret(.accessToken))
            XCTAssertFalse(String(describing: error).contains("secret-token"))
            XCTAssertFalse(String(describing: error).contains("rotated-token"))
        }

        XCTAssertEqual(try store.delete(.accessToken), .deleted)
        XCTAssertThrowsError(try store.read(.accessToken)) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
            XCTAssertFalse(String(describing: error).contains("rotated-token"))
        }
    }

    func testKeychainProtectedActionValueStoreRoundsTripsAndDeletesValues() throws {
        let secretStore = KeychainSecretStore(service: "dev.perchha.tests.\(UUID().uuidString)")
        let store = KeychainProtectedActionValueStore(secretStore: secretStore)
        let first: ProtectedActionValueReference = "action.pin"
        let second: ProtectedActionValueReference = "action.code"

        XCTAssertNoThrow(try store.delete(first))
        XCTAssertNoThrow(try store.delete(second))
        XCTAssertThrowsError(try store.load(first)) { error in
            XCTAssertEqual(error as? ProtectedActionValueStoreError, .missingValue(first))
        }

        XCTAssertNoThrow(try store.save("1234", for: first))
        XCTAssertEqual(try store.load(first), "1234")
        XCTAssertNoThrow(try store.save("5678", for: first))
        XCTAssertEqual(try store.load(first), "5678")
        XCTAssertNoThrow(try store.save("abcd", for: second))
        XCTAssertEqual(try store.load(second), "abcd")

        XCTAssertNoThrow(try store.delete(first))
        XCTAssertThrowsError(try store.load(first)) { error in
            XCTAssertEqual(error as? ProtectedActionValueStoreError, .missingValue(first))
        }
        XCTAssertEqual(try store.load(second), "abcd")
        XCTAssertNoThrow(try store.delete(second))
    }

    func testAuthSessionStoreSavesRotatesLoadsAndClearsTokens() throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.tests.\(UUID().uuidString)")
        let store = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? store.clear()
        }

        let session = try PerchHAAuthSession(
            accessToken: " access-token ",
            refreshToken: " refresh-token ",
            clientID: " https://perchha.dev/app "
        )

        XCTAssertEqual(
            try store.save(session),
            PerchHAAuthSessionWriteResult(accessToken: .created, refreshToken: .created)
        )
        XCTAssertEqual(
            try store.load(),
            try PerchHAAuthSession(
                accessToken: "access-token",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        XCTAssertEqual(try store.replaceAccessToken(" rotated-access-token "), .updated)
        XCTAssertEqual(
            try store.load(),
            try PerchHAAuthSession(
                accessToken: "rotated-access-token",
                refreshToken: "refresh-token",
                clientID: "https://perchha.dev/app"
            )
        )
        XCTAssertEqual(
            try store.clear(),
            PerchHAAuthSessionClearResult(accessToken: .deleted, refreshToken: .deleted)
        )
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.accessToken))
        }
    }

    func testAuthSessionRejectsEmptyTokensBeforeWritingToKeychain() throws {
        XCTAssertThrowsError(try PerchHAAuthSession(accessToken: "", refreshToken: "refresh-token")) { error in
            XCTAssertEqual(error as? SecretStoreError, .emptySecret(.accessToken))
        }
        XCTAssertThrowsError(try PerchHAAuthSession(accessToken: "access-token", refreshToken: " ")) { error in
            XCTAssertEqual(error as? SecretStoreError, .emptySecret(.refreshToken))
        }
        XCTAssertThrowsError(try PerchHAAuthSession(accessToken: "access-token", refreshToken: "refresh-token", clientID: " ")) { error in
            XCTAssertEqual(error as? SecretStoreError, .emptySecret(.oauthClientID))
        }
    }

    func testAuthSessionStoreCanPersistStandaloneAccessTokenForLongLivedAuth() throws {
        let keychain = KeychainSecretStore(service: "dev.perchha.tests.\(UUID().uuidString)")
        let store = PerchHAAuthSessionStore(secretStore: keychain)
        defer {
            _ = try? store.clear()
        }

        _ = try store.save(
            PerchHAAuthSession(
                accessToken: "oauth-access",
                refreshToken: "oauth-refresh",
                clientID: "https://perchha.dev/app"
            )
        )

        XCTAssertEqual(try store.saveAccessToken(" long-lived-token "), .updated)
        XCTAssertEqual(try store.loadAccessToken(), "long-lived-token")
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? SecretStoreError, .notFound(.refreshToken))
        }
    }

    func testAuthSessionSaveRestoresPreviousAccessTokenWhenRefreshWriteFails() throws {
        let secretStore = FailureInjectingSecretStore()
        XCTAssertEqual(try secretStore.save("old-access", for: .accessToken), .created)
        XCTAssertEqual(try secretStore.save("old-refresh", for: .refreshToken), .created)
        XCTAssertEqual(try secretStore.save("old-client", for: .oauthClientID), .created)
        secretStore.saveFailures[.refreshToken] = .operationFailed(operation: "save", secret: .refreshToken, status: -50)
        let sessionStore = PerchHAAuthSessionStore(secretStore: secretStore)

        XCTAssertThrowsError(
            try sessionStore.save(
                try PerchHAAuthSession(
                    accessToken: "new-access",
                    refreshToken: "new-refresh",
                    clientID: "new-client"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SecretStoreError,
                .operationFailed(operation: "save", secret: .refreshToken, status: -50)
            )
        }
        XCTAssertEqual(try secretStore.read(.accessToken), "old-access")
        XCTAssertEqual(try secretStore.read(.refreshToken), "old-refresh")
        XCTAssertEqual(try secretStore.read(.oauthClientID), "old-client")
    }

    func testAuthSessionSaveRestoresFullSessionWhenClientIDWriteFails() throws {
        let secretStore = FailureInjectingSecretStore()
        XCTAssertEqual(try secretStore.save("old-access", for: .accessToken), .created)
        XCTAssertEqual(try secretStore.save("old-refresh", for: .refreshToken), .created)
        XCTAssertEqual(try secretStore.save("old-client", for: .oauthClientID), .created)
        secretStore.saveFailures[.oauthClientID] = .operationFailed(operation: "save", secret: .oauthClientID, status: -50)
        let sessionStore = PerchHAAuthSessionStore(secretStore: secretStore)

        XCTAssertThrowsError(
            try sessionStore.save(
                try PerchHAAuthSession(
                    accessToken: "new-access",
                    refreshToken: "new-refresh",
                    clientID: "new-client"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SecretStoreError,
                .operationFailed(operation: "save", secret: .oauthClientID, status: -50)
            )
        }
        XCTAssertEqual(try secretStore.read(.accessToken), "old-access")
        XCTAssertEqual(try secretStore.read(.refreshToken), "old-refresh")
        XCTAssertEqual(try secretStore.read(.oauthClientID), "old-client")
    }

    func testAuthSessionClearRestoresAccessTokenWhenRefreshDeleteFails() throws {
        let secretStore = FailureInjectingSecretStore()
        XCTAssertEqual(try secretStore.save("old-access", for: .accessToken), .created)
        XCTAssertEqual(try secretStore.save("old-refresh", for: .refreshToken), .created)
        XCTAssertEqual(try secretStore.save("old-client", for: .oauthClientID), .created)
        secretStore.deleteFailures[.refreshToken] = .operationFailed(operation: "delete", secret: .refreshToken, status: -50)
        let sessionStore = PerchHAAuthSessionStore(secretStore: secretStore)

        XCTAssertThrowsError(try sessionStore.clear()) { error in
            XCTAssertEqual(
                error as? SecretStoreError,
                .operationFailed(operation: "delete", secret: .refreshToken, status: -50)
            )
        }
        XCTAssertEqual(try secretStore.read(.accessToken), "old-access")
        XCTAssertEqual(try secretStore.read(.refreshToken), "old-refresh")
        XCTAssertEqual(try secretStore.read(.oauthClientID), "old-client")
    }

    func testAuthSessionClearRestoresFullSessionWhenClientIDDeleteFails() throws {
        let secretStore = FailureInjectingSecretStore()
        XCTAssertEqual(try secretStore.save("old-access", for: .accessToken), .created)
        XCTAssertEqual(try secretStore.save("old-refresh", for: .refreshToken), .created)
        XCTAssertEqual(try secretStore.save("old-client", for: .oauthClientID), .created)
        secretStore.deleteFailures[.oauthClientID] = .operationFailed(operation: "delete", secret: .oauthClientID, status: -50)
        let sessionStore = PerchHAAuthSessionStore(secretStore: secretStore)

        XCTAssertThrowsError(try sessionStore.clear()) { error in
            XCTAssertEqual(
                error as? SecretStoreError,
                .operationFailed(operation: "delete", secret: .oauthClientID, status: -50)
            )
        }
        XCTAssertEqual(try secretStore.read(.accessToken), "old-access")
        XCTAssertEqual(try secretStore.read(.refreshToken), "old-refresh")
        XCTAssertEqual(try secretStore.read(.oauthClientID), "old-client")
    }

    func testLegacyConnectionProfileDecodesIntoOrderedAddresses() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "connectionProfile": {
            "urlString": "https://home.local:8123",
            "fallbackURLString": "https://remote.example/ha"
          }
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let configuration = try JSONConfigStore(fileURL: url).load()
        let profile = try XCTUnwrap(configuration.connectionProfile)

        XCTAssertEqual(
            profile.addresses,
            [
                PerchHAConnectionAddress(urlString: "https://home.local:8123"),
                PerchHAConnectionAddress(urlString: "https://remote.example/ha")
            ]
        )
        XCTAssertEqual(profile.urlString, "https://home.local:8123")
        XCTAssertEqual(profile.fallbackURLString, "https://remote.example/ha")
    }

    func testLegacyConnectionProfileWithEmptyFallbackDecodesToSingleAddress() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "connectionProfile": {
            "urlString": "https://home.local:8123",
            "fallbackURLString": ""
          }
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let configuration = try JSONConfigStore(fileURL: url).load()
        let profile = try XCTUnwrap(configuration.connectionProfile)

        XCTAssertEqual(profile.addresses, [PerchHAConnectionAddress(urlString: "https://home.local:8123")])
        XCTAssertEqual(profile.fallbackURLString, "")
    }

    func testConnectionProfileWithMultipleAddressesRoundTrips() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let configuration = PerchHAConfiguration(
            connectionProfile: PerchHAConnectionProfile(addresses: [
                PerchHAConnectionAddress(label: "Home", urlString: "https://home.local:8123"),
                PerchHAConnectionAddress(label: "VPN", urlString: "https://vpn.example/ha"),
                PerchHAConnectionAddress(label: "Remote", urlString: "https://remote.example")
            ])
        )
        let store = JSONConfigStore(fileURL: url)

        XCTAssertEqual(try store.save(configuration), configuration)
        XCTAssertEqual(try store.load(), configuration)
    }

    func testConnectionProfileRoundTripsStrictCertificateValidationChoice() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        // Strict validation is the non-default choice now; it must survive the
        // round trip rather than silently reverting to the trusting default.
        let configuration = PerchHAConfiguration(
            connectionProfile: PerchHAConnectionProfile(
                addresses: [PerchHAConnectionAddress(urlString: "https://home.local:8123")],
                allowsSelfSignedCertificates: false
            )
        )
        let store = JSONConfigStore(fileURL: url)

        XCTAssertEqual(try store.save(configuration), configuration)
        let loaded = try XCTUnwrap(try store.load().connectionProfile)
        XCTAssertFalse(loaded.allowsSelfSignedCertificates)
    }

    func testConnectionProfileWithoutSelfSignedFieldDecodesAsTrusting() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "connectionProfile": {
            "addresses": [{"label": "", "urlString": "https://home.local:8123"}]
          }
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let profile = try XCTUnwrap(try JSONConfigStore(fileURL: url).load().connectionProfile)
        XCTAssertTrue(profile.allowsSelfSignedCertificates, "profiles from before the field default to the trusting posture")
    }

    func testLegacyConnectionProfileDecodesAsTrustingSelfSignedCertificates() throws {
        let url = temporaryConfigURL()
        defer {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        let json = """
        {
          "schemaVersion": 1,
          "connectionProfile": {
            "urlString": "https://home.local:8123",
            "fallbackURLString": ""
          }
        }
        """
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: url)

        let profile = try XCTUnwrap(try JSONConfigStore(fileURL: url).load().connectionProfile)
        XCTAssertTrue(profile.allowsSelfSignedCertificates)
    }

    private func temporaryConfigURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-persistence-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }
}

final class FailureInjectingSecretStore: SecretStore, @unchecked Sendable {
    var saveFailures: [PerchHASecret: SecretStoreError] = [:]
    var deleteFailures: [PerchHASecret: SecretStoreError] = [:]
    private var values: [PerchHASecret: String] = [:]

    @discardableResult
    func save(_ value: String, for secret: PerchHASecret) throws -> SecretWriteResult {
        if let failure = saveFailures[secret] {
            throw failure
        }
        guard !value.isEmpty else {
            throw SecretStoreError.emptySecret(secret)
        }
        let result: SecretWriteResult = values[secret] == nil ? .created : .updated
        values[secret] = value
        return result
    }

    func read(_ secret: PerchHASecret) throws -> String {
        guard let value = values[secret] else {
            throw SecretStoreError.notFound(secret)
        }
        return value
    }

    @discardableResult
    func delete(_ secret: PerchHASecret) throws -> SecretDeleteResult {
        if let failure = deleteFailures[secret] {
            throw failure
        }
        guard values.removeValue(forKey: secret) != nil else {
            return .notFound
        }
        return .deleted
    }
}
#endif
