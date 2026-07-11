#if canImport(XCTest)
import XCTest
import PearchHACore
import PearchHASupport

final class PearchHACoreTests: XCTestCase {
    func testActionValueRoundTripsNestedJSONShapes() throws {
        let payload: ActionValue = .object([
            "sequence": .array([
                .object([
                    "service": "light.turn_on",
                    "data": .object([
                        "brightness": 120,
                        "transition": 1.5,
                        "enabled": true,
                        "note": .null
                    ])
                ])
            ])
        ])

        let encoded = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(ActionValue.self, from: encoded)

        XCTAssertEqual(decoded, payload)
    }

    func testActionValueRoundTripsProtectedReferenceEnvelope() throws {
        let payload: ActionValue = .object([
            "alarm_code": .protectedString("protected-ref")
        ])

        let encoded = try JSONEncoder().encode(payload)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let decoded = try JSONDecoder().decode(ActionValue.self, from: encoded)

        XCTAssertTrue(text.contains(#""$pearchha":"protected_string""#))
        XCTAssertTrue(text.contains(#""reference":"protected-ref""#))
        XCTAssertEqual(decoded, payload)
    }

    func testActionSpecResolvesProtectedReferencesAndCollectsReferenceSet() throws {
        let action = ActionSpec(
            domain: "alarm_control_panel",
            service: "alarm_arm_home",
            targetEntityID: "alarm_control_panel.home",
            serviceData: [
                "payload": .object([
                    "pin": .protectedString("pin-ref"),
                    "label": "home"
                ])
            ]
        )

        let resolved = try action.resolvedProtectedValues { reference in
            XCTAssertEqual(reference, "pin-ref")
            return "1234"
        }

        XCTAssertEqual(action.protectedValueReferences, ["pin-ref"])
        XCTAssertEqual(
            resolved.serviceData,
            [
                "payload": .object([
                    "pin": "1234",
                    "label": "home"
                ])
            ]
        )
    }

    func testEntityIDPreservesRawValue() {
        let id: EntityID = "sensor.office_temperature"

        XCTAssertEqual(id.rawValue, "sensor.office_temperature")
    }

    func testEntityStateSupportsMissingUnits() {
        let state = EntityState(
            id: "binary_sensor.window",
            name: "Window",
            state: "off",
            unit: nil
        )

        XCTAssertNil(state.unit)
        XCTAssertEqual(state.name, "Window")
    }

    func testRoomResolverUsesEntityAreaBeforeDeviceArea() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [
                    Area(id: "kitchen", name: "Kitchen"),
                    Area(id: "living_room", name: "Living Room")
                ],
                devices: [
                    Device(id: "thermostat", name: "Thermostat", areaID: "living_room")
                ],
                entities: [
                    EntityRegistryEntry(
                        id: "sensor.temperature",
                        name: "Temperature",
                        areaID: "kitchen",
                        deviceID: "thermostat"
                    )
                ],
                states: [
                    EntityState(id: "sensor.temperature", name: "Fallback", state: "21.4", unit: "°C")
                ]
            )
        )

        XCTAssertEqual(rooms.map(\.name), ["Kitchen"])
        XCTAssertEqual(rooms.first?.entities.map(\.id), ["sensor.temperature"])
    }

    func testRoomResolverUsesDeviceAreaWhenEntityAreaIsMissing() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [
                    Area(id: "office", name: "Office")
                ],
                devices: [
                    Device(
                        id: "air_sensor",
                        name: "O-1PPT",
                        manufacturer: "AirGradient",
                        model: "AirGradient Open Air",
                        domain: "bluetooth",
                        areaID: "office"
                    )
                ],
                entities: [
                    EntityRegistryEntry(id: "sensor.co2", name: nil, areaID: nil, deviceID: "air_sensor")
                ],
                states: [
                    EntityState(id: "sensor.co2", name: "CO2", state: "650", unit: "ppm")
                ]
            )
        )

        XCTAssertEqual(rooms.map(\.name), ["Office"])
        XCTAssertEqual(rooms.first?.entities.first?.name, "CO2")
        XCTAssertEqual(rooms.first?.entities.first?.deviceName, "O-1PPT")
        XCTAssertEqual(rooms.first?.entities.first?.deviceManufacturer, "AirGradient")
        XCTAssertEqual(rooms.first?.entities.first?.deviceModel, "AirGradient Open Air")
        XCTAssertEqual(rooms.first?.entities.first?.deviceDomain, "bluetooth")
    }

    func testRoomResolverPlacesUnassignedEntitiesLast() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [
                    Area(id: "garage", name: "Garage")
                ],
                devices: [],
                entities: [
                    EntityRegistryEntry(id: "switch.garage_light", name: "Garage light", areaID: "garage", deviceID: nil)
                ],
                states: [
                    EntityState(id: "binary_sensor.loose", name: "Loose", state: "off", unit: nil),
                    EntityState(id: "switch.garage_light", name: "Garage light", state: "on", unit: nil)
                ]
            )
        )

        XCTAssertEqual(rooms.map(\.name), ["Garage", "Unassigned"])
        XCTAssertEqual(rooms.last?.id, RoomResolver.unassignedRoomID)
        XCTAssertEqual(rooms.last?.entities.map(\.id), ["binary_sensor.loose"])
    }

    func testRoomResolverDoesNotTrapOnDuplicateRegistryIDs() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [
                    Area(id: "office", name: "Office"),
                    Area(id: "office", name: "Duplicate Office")
                ],
                devices: [
                    Device(id: "bridge", name: "Bridge", areaID: "office"),
                    Device(id: "bridge", name: "Duplicate Bridge", areaID: nil)
                ],
                entities: [
                    EntityRegistryEntry(id: "sensor.temperature", name: "Temperature", areaID: nil, deviceID: "bridge"),
                    EntityRegistryEntry(id: "sensor.temperature", name: "Duplicate", areaID: nil, deviceID: nil)
                ],
                states: [
                    EntityState(id: "sensor.temperature", name: "Fallback", state: "20", unit: "°C")
                ]
            )
        )

        XCTAssertEqual(rooms.map(\.name), ["Office"])
        XCTAssertEqual(rooms.first?.entities.first?.name, "Temperature")
    }

    func testRoomResolverPrefersMoreSpecificStateNameOverGenericRegistryName() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [
                    Area(id: "office", name: "Office")
                ],
                devices: [],
                entities: [
                    EntityRegistryEntry(
                        id: "sensor.shellyplugsg3_e4b063fa527c_leistung",
                        name: "Leistung",
                        areaID: "office",
                        deviceID: nil
                    )
                ],
                states: [
                    EntityState(
                        id: "sensor.shellyplugsg3_e4b063fa527c_leistung",
                        name: "Deskyuna Leistung",
                        state: "87.7",
                        unit: "W"
                    )
                ]
            )
        )

        XCTAssertEqual(rooms.first?.entities.first?.name, "Deskyuna Leistung")
    }

    func testSelectionProjectorBuildsSearchableCheckboxTree() {
        let tree = EntitySelectionProjector().selectionTree(
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature"],
                roomOrder: ["kitchen", "office"],
                entityOrder: ["sensor.office_temperature", "switch.kitchen_light"],
                isExplicit: true
            ),
            query: "office"
        )

        XCTAssertEqual(tree.map(\.name), ["Office"])
        XCTAssertEqual(tree.first?.entities.map(\.entity.id), ["sensor.office_temperature", "sensor.office_humidity"])
        XCTAssertEqual(tree.first?.entities.map(\.isSelected), [true, false])
    }

    func testSelectionProjectorSearchMatchesDeviceMetadata() {
        let tree = EntitySelectionProjector().selectionTree(
            rooms: [
                Room(
                    id: "office",
                    name: "Office",
                    entities: [
                        DiscoveredEntity(
                            id: "sensor.office_co2",
                            name: "CO2",
                            state: "650",
                            unit: "ppm",
                            areaID: "office",
                            deviceID: "office_air",
                            deviceName: "O-1PPT",
                            deviceManufacturer: "AirGradient",
                            deviceModel: "AirGradient Open Air",
                            deviceDomain: "bluetooth"
                        )
                    ]
                )
            ],
            configuration: EntitySelectionConfiguration(isExplicit: true),
            query: "o-1ppt"
        )

        XCTAssertEqual(tree.map(\.name), ["Office"])
        XCTAssertEqual(tree.first?.entities.map(\.entity.id), ["sensor.office_co2"])
    }

    func testSelectionProjectorSearchMatchesDeviceManufacturerModelAndDomain() {
        let rooms = [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.office_co2",
                        name: "CO2",
                        state: "650",
                        unit: "ppm",
                        areaID: "office",
                        deviceID: "office_air",
                        deviceName: "O-1PPT",
                        deviceManufacturer: "AirGradient",
                        deviceModel: "AirGradient Open Air",
                        deviceDomain: "bluetooth"
                    )
                ]
            )
        ]

        let modelTree = EntitySelectionProjector().selectionTree(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(isExplicit: true),
            query: "airgradient"
        )
        let manufacturerTree = EntitySelectionProjector().selectionTree(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(isExplicit: true),
            query: "o-1ppt"
        )
        let domainTree = EntitySelectionProjector().selectionTree(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(isExplicit: true),
            query: "bluetooth"
        )

        XCTAssertEqual(modelTree.first?.entities.map(\.entity.id), ["sensor.office_co2"])
        XCTAssertEqual(manufacturerTree.first?.entities.map(\.entity.id), ["sensor.office_co2"])
        XCTAssertEqual(domainTree.first?.entities.map(\.entity.id), ["sensor.office_co2"])
    }

    func testSelectionProjectorAppliesRoomAndEntityOrderToSelectedRooms() {
        let rooms = EntitySelectionProjector().selectedRooms(
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"],
                roomOrder: ["kitchen", "office"],
                entityOrder: ["sensor.office_humidity", "sensor.office_temperature", "switch.kitchen_light"],
                isExplicit: true
            )
        )

        XCTAssertEqual(rooms.map(\.id), ["kitchen", "office"])
        XCTAssertEqual(rooms.flatMap(\.entities).map(\.id), [
            "switch.kitchen_light",
            "sensor.office_humidity",
            "sensor.office_temperature"
        ])
    }

    func testSelectionProjectorReturnsNoSelectedRoomsWhenNothingIsChecked() {
        let rooms = EntitySelectionProjector().selectedRooms(
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(isExplicit: true)
        )

        XCTAssertEqual(rooms, [])
    }

    func testSelectionReordererMovesRoomsAndSelectionOrder() {
        let configuration = EntitySelectionReorderer().moveRoom(
            "kitchen",
            direction: .up,
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                roomOrder: ["office", "kitchen"],
                entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            )
        )

        XCTAssertEqual(configuration.roomOrder, ["kitchen", "office"])
        XCTAssertEqual(configuration.entityOrder, ["switch.kitchen_light", "sensor.office_temperature", "sensor.office_humidity"])
        XCTAssertEqual(configuration.selectedEntityIDs, ["switch.kitchen_light", "sensor.office_temperature", "sensor.office_humidity"])
        XCTAssertTrue(configuration.isExplicit)
    }

    func testSelectionReordererMovesEntitiesWithinRoom() {
        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_humidity",
            direction: .up,
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity"],
                roomOrder: ["office", "kitchen"],
                entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            )
        )

        XCTAssertEqual(configuration.roomOrder, ["office", "kitchen"])
        XCTAssertEqual(configuration.entityOrder, ["sensor.office_humidity", "sensor.office_temperature", "switch.kitchen_light"])
        XCTAssertEqual(configuration.selectedEntityIDs, ["sensor.office_humidity", "sensor.office_temperature"])
        XCTAssertTrue(configuration.isExplicit)
    }

    func testSelectionReordererLeavesBoundaryMovesUntouched() {
        let original = EntitySelectionConfiguration(
            selectedEntityIDs: ["sensor.office_temperature"],
            roomOrder: ["office", "kitchen"],
            entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
            isExplicit: true
        )

        let configuration = EntitySelectionReorderer().moveRoom(
            "office",
            direction: .up,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func testSelectionReordererPlacesRoomsRelativeToDropTarget() {
        let configuration = EntitySelectionReorderer().moveRoom(
            "office",
            relativeTo: "kitchen",
            placement: .after,
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                roomOrder: ["office", "kitchen"],
                entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            )
        )

        XCTAssertEqual(configuration.roomOrder, ["kitchen", "office"])
        XCTAssertEqual(configuration.entityOrder, ["switch.kitchen_light", "sensor.office_temperature", "sensor.office_humidity"])
        XCTAssertEqual(configuration.selectedEntityIDs, ["switch.kitchen_light", "sensor.office_temperature", "sensor.office_humidity"])
    }

    func testSelectionReordererPlacesEntitiesRelativeToDropTargetWithinRoom() {
        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_temperature",
            relativeTo: "sensor.office_humidity",
            placement: .after,
            rooms: selectionRooms(),
            configuration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity"],
                roomOrder: ["office", "kitchen"],
                entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            )
        )

        XCTAssertEqual(configuration.entityOrder, ["sensor.office_humidity", "sensor.office_temperature", "switch.kitchen_light"])
        XCTAssertEqual(configuration.selectedEntityIDs, ["sensor.office_humidity", "sensor.office_temperature"])
    }

    func testSelectionReordererIgnoresEntityDropsAcrossRooms() {
        let original = EntitySelectionConfiguration(
            selectedEntityIDs: ["sensor.office_temperature", "switch.kitchen_light"],
            roomOrder: ["office", "kitchen"],
            entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
            isExplicit: true
        )

        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_temperature",
            relativeTo: "switch.kitchen_light",
            placement: .after,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func test_t_value_rendering_states() {
        let formatter = EntityValueFormatter(locale: Locale(identifier: "de_DE"), maximumFractionDigits: 1)

        XCTAssertEqual(
            formatter.format(entity("sensor.temperature", state: "21.45", unit: "°C")),
            FormattedEntityValue(text: "21,5 °C", status: .available)
        )
        XCTAssertEqual(
            formatter.format(entity("sensor.window", state: "unavailable", unit: nil)),
            FormattedEntityValue(text: "Unavailable", status: .unavailable)
        )
        XCTAssertEqual(
            formatter.format(entity("sensor.battery", state: "unknown", unit: "%")),
            FormattedEntityValue(text: "Unknown", status: .unknown)
        )
        XCTAssertEqual(
            formatter.format(entity("sensor.temperature", state: "21.45", unit: "°C"), isStale: true),
            FormattedEntityValue(text: "Stale: 21,5 °C", status: .stale)
        )
    }

    func test_t_gauge_rendering_humidity_battery() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.office_humidity", name: "Office humidity", state: "44", unit: "%"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.office_humidity",
                style: .battery
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "BAT[####------] 44%")
        XCTAssertEqual(rendered.gauge, MenuBarGauge(percent: 44, filledSegments: 4, segmentCount: 10))
        XCTAssertEqual(rendered.severity, .normal)
        XCTAssertEqual(rendered.accessibilityLabel, "Office humidity, 44%, 44 percent, battery")
    }

    func testMenuBarRendererRendersAbsoluteRingWithExplicitTotal() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.energy_today", name: "Energy today", state: "30", unit: "kWh"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .ring,
                absoluteTotal: 120
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "RING 25%")
        XCTAssertEqual(rendered.gauge, MenuBarGauge(percent: 25, filledSegments: 3, segmentCount: 10))
        XCTAssertEqual(rendered.accessibilityLabel, "Energy today, 30 kWh, 25 percent, ring")
    }

    func testMenuBarRendererUsesTotalEntityForAbsoluteGauges() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.energy_today", name: "Energy today", state: "30", unit: "kWh"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .bar,
                totalEntityID: "sensor.energy_budget"
            ),
            availableEntities: [
                entity("sensor.energy_budget", name: "Energy budget", state: "60", unit: "kWh")
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "BAR[#####-----] 50%")
        XCTAssertEqual(rendered.gauge, MenuBarGauge(percent: 50, filledSegments: 5, segmentCount: 10))
    }

    func testMenuBarRendererRejectsIncompatibleTotalEntityForAbsoluteGauges() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.energy_today", name: "Energy today", state: "30", unit: "kWh"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .bar,
                totalEntityID: "sensor.office_humidity"
            ),
            availableEntities: [
                entity("sensor.office_humidity", name: "Office humidity", state: "44", unit: "%")
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "30 kWh")
        XCTAssertNil(rendered.gauge)
    }

    func testMenuBarRendererClampsPercentageGauge() {
        let high = MenuBarItemRenderer().render(
            entity: entity("sensor.humidity", name: "Humidity", state: "140", unit: "%"),
            configuration: MenuBarItemConfiguration(entityID: "sensor.humidity", style: .bar),
            locale: Locale(identifier: "en_US")
        )
        let low = MenuBarItemRenderer().render(
            entity: entity("sensor.humidity", name: "Humidity", state: "-8", unit: "%"),
            configuration: MenuBarItemConfiguration(entityID: "sensor.humidity", style: .bar),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(high.gauge, MenuBarGauge(percent: 100, filledSegments: 10, segmentCount: 10))
        XCTAssertEqual(low.gauge, MenuBarGauge(percent: 0, filledSegments: 0, segmentCount: 10))
    }

    func testMenuBarRendererFallsBackToTextWhenGaugeIsLocked() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.energy_today", name: "Energy today", state: "30", unit: "kWh"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .ring,
                showsLabel: true
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "Energy today 30 kWh")
        XCTAssertNil(rendered.gauge)
        XCTAssertEqual(rendered.style, .ring)
    }

    func testMenuBarRendererAppliesThresholdSeverity() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.battery", name: "Battery", state: "15", unit: "%"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.battery",
                style: .battery,
                thresholds: ValueThresholds(
                    warning: ValueThreshold(value: 30, direction: .belowOrEqual),
                    critical: ValueThreshold(value: 20, direction: .belowOrEqual)
                )
            ),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.severity, .critical)
        XCTAssertEqual(rendered.accessibilityLabel, "Battery, 15%, 15 percent, critical, battery")
    }

    func testMenuBarRendererClassifiesSemanticStringStates() {
        let rendered = MenuBarItemRenderer().render(
            entity: entity("sensor.air_quality", name: "Air quality", state: "BAD", unit: nil),
            configuration: MenuBarItemConfiguration(entityID: "sensor.air_quality"),
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.severity, .critical)
        XCTAssertTrue(rendered.accessibilityLabel.contains("critical"))
    }

    func testEntityDisplayDefaultsSemanticStateSeverityHandlesGoodMediumBad() {
        XCTAssertEqual(EntityDisplayDefaults.semanticStateSeverity(for: "GOOD"), .normal)
        XCTAssertEqual(EntityDisplayDefaults.semanticStateSeverity(for: "MEDIUM"), .warning)
        XCTAssertEqual(EntityDisplayDefaults.semanticStateSeverity(for: "BAD"), .critical)
    }

    func testMenuBarItemProjectorPromotesConfiguredEntitiesInOrder() {
        let promoted = MenuBarItemProjector().promotedEntities(
            rooms: selectionRooms(),
            menuBarEntityIDs: ["sensor.missing", "switch.kitchen_light", "sensor.office_humidity"]
        )

        XCTAssertEqual(promoted.map(\.id), ["switch.kitchen_light", "sensor.office_humidity"])
    }

    func testMenuBarDisplayConfigurationDefaultsPromotionsAndReplacesItems() {
        let display = MenuBarDisplayConfiguration(
            promotedEntityIDs: ["sensor.office_humidity", "sensor.office_humidity"],
            itemConfigurations: [
                MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .battery),
                MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .ring)
            ]
        )

        XCTAssertEqual(display.promotedEntityIDs, ["sensor.office_humidity"])
        XCTAssertEqual(display.itemConfiguration(for: "sensor.office_humidity").style, .battery)
        XCTAssertEqual(display.itemConfiguration(for: "sensor.office_temperature").style, .text)

        let hidden = display.settingPromotion("sensor.office_humidity", isPromoted: false)
        XCTAssertEqual(hidden.promotedEntityIDs, [])

        let replaced = display.replacingItemConfiguration(
            MenuBarItemConfiguration(
                entityID: "sensor.office_humidity",
                style: .ring,
                showsLabel: true,
                showsUnit: false,
                maximumFractionDigits: 2
            )
        )
        XCTAssertEqual(replaced.itemConfiguration(for: "sensor.office_humidity").style, .ring)
        XCTAssertTrue(replaced.itemConfiguration(for: "sensor.office_humidity").showsLabel)
        XCTAssertFalse(replaced.itemConfiguration(for: "sensor.office_humidity").showsUnit)
        XCTAssertEqual(replaced.itemConfiguration(for: "sensor.office_humidity").maximumFractionDigits, 2)
    }

    func testMenuBarDisplayConfigurationMovesPromotedItems() {
        let display = MenuBarDisplayConfiguration(
            promotedEntityIDs: [
                "sensor.office_temperature",
                "sensor.office_humidity",
                "sensor.energy_today"
            ],
            itemConfigurations: [
                MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .battery)
            ]
        )

        XCTAssertEqual(
            display.movingPromotion("sensor.office_humidity", direction: .up).promotedEntityIDs,
            ["sensor.office_humidity", "sensor.office_temperature", "sensor.energy_today"]
        )
        XCTAssertEqual(
            display.movingPromotion("sensor.office_humidity", direction: .down).promotedEntityIDs,
            ["sensor.office_temperature", "sensor.energy_today", "sensor.office_humidity"]
        )
        XCTAssertEqual(
            display.movingPromotion("sensor.energy_today", relativeTo: "sensor.office_temperature", placement: .before).promotedEntityIDs,
            ["sensor.energy_today", "sensor.office_temperature", "sensor.office_humidity"]
        )
        XCTAssertEqual(
            display.movingPromotion("sensor.office_temperature", direction: .up),
            display
        )
        XCTAssertEqual(
            display.movingPromotion("sensor.missing", direction: .down),
            display
        )
        XCTAssertEqual(
            display.movingPromotion("sensor.office_humidity", relativeTo: "sensor.missing", placement: .after),
            display
        )
        XCTAssertEqual(display.itemConfiguration(for: "sensor.office_humidity").style, .battery)
    }

    func testMenuBarItemConfigurationClearsTotalsAndThresholdsExplicitly() {
        let configuration = MenuBarItemConfiguration(
            entityID: "sensor.energy_today",
            style: .ring,
            absoluteTotal: 120,
            thresholds: ValueThresholds(
                warning: ValueThreshold(value: 80),
                critical: ValueThreshold(value: 90)
            ),
            defaultHistoryRange: .day
        )

        let totalEntityConfiguration = configuration.settingTotalEntityID("sensor.energy_budget")
        XCTAssertNil(totalEntityConfiguration.absoluteTotal)
        XCTAssertEqual(totalEntityConfiguration.totalEntityID, "sensor.energy_budget")
        XCTAssertEqual(totalEntityConfiguration.defaultHistoryRange, .day)

        let manualTotalConfiguration = totalEntityConfiguration.settingAbsoluteTotal(240)
        XCTAssertEqual(manualTotalConfiguration.absoluteTotal, 240)
        XCTAssertNil(manualTotalConfiguration.totalEntityID)
        XCTAssertEqual(manualTotalConfiguration.defaultHistoryRange, .day)

        let cleared = manualTotalConfiguration
            .settingAbsoluteTotal(nil)
            .settingWarningThreshold(nil)
            .settingCriticalThreshold(nil)
        XCTAssertNil(cleared.absoluteTotal)
        XCTAssertNil(cleared.totalEntityID)
        XCTAssertTrue(cleared.thresholds.steps.isEmpty)
        XCTAssertEqual(cleared.defaultHistoryRange, .day)

        XCTAssertEqual(cleared.settingDefaultHistoryRange(.month).defaultHistoryRange, .month)
    }

    private func selectionRooms() -> [Room] {
        [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    entity("sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C"),
                    entity("sensor.office_humidity", name: "Office humidity", state: "44", unit: "%")
                ]
            ),
            Room(
                id: "kitchen",
                name: "Kitchen",
                entities: [
                    entity("switch.kitchen_light", name: "Kitchen light", state: "off", unit: nil)
                ]
            )
        ]
    }

    func test_t_item_configuration_per_metric_defaults() {
        let configuration = MenuBarItemConfiguration(entityID: "sensor.any")

        XCTAssertEqual(configuration.coverControlMode, .both)
        XCTAssertNil(configuration.displayUnit)
        XCTAssertNil(configuration.minValue)
        XCTAssertNil(configuration.maxValue)
        XCTAssertEqual(configuration.style, .text)
        XCTAssertEqual(configuration.maximumFractionDigits, 1)
    }

    func testEntityDisplayDefaultsApplyTemperatureThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.office_temperature",
            name: "Office temperature",
            state: "21.4",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )

        let configuration = EntityDisplayDefaults.configuration(for: entity)

        XCTAssertEqual(configuration.maximumFractionDigits, 1)
        XCTAssertEqual(
            configuration.thresholds,
            ValueThresholds(
                steps: [
                    ThresholdStep(
                        value: 18,
                        color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)
                    ),
                    ThresholdStep(value: 21, color: ValueThresholds.okColor),
                    ThresholdStep(value: 25, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 28, color: ValueThresholds.criticalColor)
                ],
                baseColor: PearchHAAccentColor(red: 0.19, green: 0.49, blue: 0.96, alpha: 1)
            )
        )
    }

    func test_t_item_configuration_round_trips_bounds() throws {
        let configuration = MenuBarItemConfiguration(
            entityID: "sensor.tank",
            displayUnit: .batteryIcon,
            minValue: 0,
            maxValue: 1000
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(MenuBarItemConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.minValue, 0)
        XCTAssertEqual(decoded.maxValue, 1000)
    }

    func test_t_item_configuration_setting_bounds() {
        let configuration = MenuBarItemConfiguration(entityID: "sensor.any")
            .settingBounds(minValue: 10, maxValue: 50)
        XCTAssertEqual(configuration.minValue, 10)
        XCTAssertEqual(configuration.maxValue, 50)
    }

    func test_t_item_configuration_setting_display_unit_to_nil() {
        let configuration = MenuBarItemConfiguration(entityID: "sensor.any", displayUnit: .bytes)
            .settingDisplayUnit(nil)
        XCTAssertNil(configuration.displayUnit)
    }

    func test_t_item_configuration_round_trips_new_fields() throws {
        let configuration = MenuBarItemConfiguration(
            entityID: "cover.blinds",
            averageEntityIDs: ["cover.blinds", "cover.blinds_2"],
            coverControlMode: .slider,
            displayUnit: .bytes,
            displayUnitSymbol: "GB"
        )

        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(MenuBarItemConfiguration.self, from: data)

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.coverControlMode, .slider)
        XCTAssertEqual(decoded.displayUnit, .bytes)
        XCTAssertEqual(decoded.displayUnitSymbol, "GB")
        XCTAssertEqual(decoded.averageEntityIDs, ["cover.blinds", "cover.blinds_2"])
    }

    func test_t_item_configuration_setting_average_entity_ids() {
        let configuration = MenuBarItemConfiguration(entityID: "sensor.any")
            .settingAverageEntityIDs(["sensor.any", "sensor.peer", "sensor.peer"])
        XCTAssertEqual(configuration.averageEntityIDs, ["sensor.any", "sensor.peer"])
    }

    func test_t_entity_averaging_uses_compatible_family_members() {
        let base = DiscoveredEntity(
            id: "sensor.temp_a",
            name: "Temp A",
            state: "20",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )
        let peer = DiscoveredEntity(
            id: "sensor.temp_b",
            name: "Temp B",
            state: "22",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )
        let mismatch = DiscoveredEntity(
            id: "sensor.humidity",
            name: "Humidity",
            state: "50",
            unit: "%",
            areaID: nil,
            deviceID: nil
        )

        let averaged = PearchHAEntityAveraging.averagedEntity(
            base: base,
            configuration: MenuBarItemConfiguration(
                entityID: base.id,
                averageEntityIDs: [base.id, peer.id, mismatch.id]
            ),
            availableEntities: [base, peer, mismatch]
        )

        XCTAssertEqual(averaged.state, "21.0")
        XCTAssertEqual(averaged.unit, "°C")
    }

    func test_t_menu_bar_renderer_formats_average_value() {
        let source = DiscoveredEntity(
            id: "sensor.temp_a",
            name: "Temp A",
            state: "20",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )
        let peer = DiscoveredEntity(
            id: "sensor.temp_b",
            name: "Temp B",
            state: "22",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )

        let rendered = MenuBarItemRenderer().render(
            entity: source,
            configuration: MenuBarItemConfiguration(
                entityID: source.id,
                averageEntityIDs: [source.id, peer.id]
            ),
            availableEntities: [source, peer],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.value.text, "21 °C")
    }

    func test_t_item_configuration_setting_display_unit() {
        let configuration = MenuBarItemConfiguration(entityID: "sensor.any")
            .settingDisplayUnit(.compact)
        XCTAssertEqual(configuration.displayUnit, .compact)
    }

    func test_t_cover_control_mode_projection() {
        XCTAssertTrue(CoverControlMode.both.showsButtons)
        XCTAssertTrue(CoverControlMode.both.showsSlider)
        XCTAssertTrue(CoverControlMode.buttons.showsButtons)
        XCTAssertFalse(CoverControlMode.buttons.showsSlider)
        XCTAssertFalse(CoverControlMode.slider.showsButtons)
        XCTAssertTrue(CoverControlMode.slider.showsSlider)
    }

    private func formatter(
        _ unit: ValueUnit?,
        decimals: Int = 0,
        showsUnit: Bool = true,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) -> EntityValueFormatter {
        EntityValueFormatter(
            locale: Locale(identifier: "en_US"),
            maximumFractionDigits: decimals,
            displayUnit: unit,
            showsUnit: showsUnit,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    func test_t_value_unit_celsius_to_fahrenheit() {
        XCTAssertEqual(
            formatter(.fahrenheit).format(entity("sensor.temp", state: "20", unit: "°C")),
            FormattedEntityValue(text: "68 °F", status: .available)
        )
    }

    func test_t_value_unit_fahrenheit_to_celsius() {
        XCTAssertEqual(
            formatter(.celsius).format(entity("sensor.temp", state: "68", unit: "F")),
            FormattedEntityValue(text: "20 °C", status: .available)
        )
    }

    func test_t_value_unit_kelvin_to_celsius() {
        XCTAssertEqual(
            formatter(.celsius, decimals: 1).format(entity("sensor.temp", state: "300", unit: "K")),
            FormattedEntityValue(text: "26.9 °C", status: .available)
        )
    }

    func test_t_value_unit_celsius_to_kelvin() {
        XCTAssertEqual(
            formatter(.kelvin, decimals: 2).format(entity("sensor.temp", state: "0", unit: "°C")),
            FormattedEntityValue(text: "273.15 K", status: .available)
        )
    }

    func test_t_value_unit_detected_temperature_keeps_small_value_unchanged() {
        XCTAssertEqual(
            formatter(nil, decimals: 1).format(entity("sensor.temp", state: "21.4", unit: "°C")),
            FormattedEntityValue(text: "21.4 °C", status: .available)
        )
    }

    func test_t_value_unit_number_keeps_small_grouped_value() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.q", state: "4054", unit: "queries")),
            FormattedEntityValue(text: "4,054 queries", status: .available)
        )
    }

    func test_t_value_unit_number_compacts_large_value() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.q", state: "4054396", unit: "queries")),
            FormattedEntityValue(text: "4.05M queries", status: .available)
        )
    }

    func test_t_value_unit_detected_number_compacts_large_value() {
        XCTAssertEqual(
            formatter(nil).format(entity("sensor.q", state: "4054396", unit: "queries")),
            FormattedEntityValue(text: "4.05M queries", status: .available)
        )
    }

    func test_t_value_unit_compact_always_compacts() {
        XCTAssertEqual(
            formatter(.compact).format(entity("sensor.q", state: "4054396", unit: "queries")),
            FormattedEntityValue(text: "4.05M queries", status: .available)
        )
    }

    func test_t_value_unit_compact_thousands_suffix() {
        XCTAssertEqual(
            formatter(.compact).format(entity("sensor.q", state: "12345", unit: nil)),
            FormattedEntityValue(text: "12.3k", status: .available)
        )
    }

    func test_t_value_unit_percent_appends_suffix() {
        XCTAssertEqual(
            formatter(.percent).format(entity("sensor.h", state: "44", unit: "%")),
            FormattedEntityValue(text: "44%", status: .available)
        )
    }

    func test_t_value_unit_bytes_renders_kilobytes() {
        XCTAssertEqual(
            formatter(.bytes).format(entity("sensor.b", state: "1536", unit: "B")),
            FormattedEntityValue(text: "1.5 KB", status: .available)
        )
    }

    func test_t_value_unit_bytes_renders_plain_bytes() {
        XCTAssertEqual(
            formatter(.bytes).format(entity("sensor.b", state: "512", unit: "B")),
            FormattedEntityValue(text: "512 B", status: .available)
        )
    }

    func test_t_value_unit_duration_renders_hours_minutes() {
        XCTAssertEqual(
            formatter(.duration).format(entity("sensor.d", state: "3725", unit: "s")),
            FormattedEntityValue(text: "1h 2m", status: .available)
        )
    }

    func test_t_value_unit_bytes_renders_petabytes() {
        XCTAssertEqual(
            formatter(.bytes).format(entity("sensor.b", state: "1125899906842624", unit: "B")),
            FormattedEntityValue(text: "1 PB", status: .available)
        )
    }

    func test_t_value_unit_data_rate_renders_kilobytes_per_second() {
        XCTAssertEqual(
            formatter(.dataRate).format(entity("sensor.net", state: "1536", unit: "B/s")),
            FormattedEntityValue(text: "1.5 KB/s", status: .available)
        )
    }

    func test_t_value_unit_data_rate_respects_reported_scaled_input_unit() {
        XCTAssertEqual(
            formatter(.dataRate).format(entity("sensor.net", state: "1536", unit: "KB/s")),
            FormattedEntityValue(text: "1.5 MB/s", status: .available)
        )
    }

    func test_t_value_unit_illuminance_compacts_large_values() {
        XCTAssertEqual(
            formatter(.illuminance).format(entity("sensor.lux", state: "12000", unit: "lx")),
            FormattedEntityValue(text: "12k lx", status: .available)
        )
    }

    func test_t_value_unit_illuminance_keeps_small_values() {
        XCTAssertEqual(
            formatter(.illuminance).format(entity("sensor.lux", state: "350", unit: "lx")),
            FormattedEntityValue(text: "350 lx", status: .available)
        )
    }

    func test_t_value_unit_power_scales_to_kilowatts() {
        XCTAssertEqual(
            formatter(.power).format(entity("sensor.p", state: "2500", unit: "W")),
            FormattedEntityValue(text: "2.5 kW", status: .available)
        )
    }

    func test_t_value_unit_power_keeps_watts() {
        XCTAssertEqual(
            formatter(.power).format(entity("sensor.p", state: "750", unit: "W")),
            FormattedEntityValue(text: "750 W", status: .available)
        )
    }

    func test_t_value_unit_energy_scales_to_kilowatt_hours() {
        XCTAssertEqual(
            formatter(.energy).format(entity("sensor.e", state: "2500", unit: "Wh")),
            FormattedEntityValue(text: "2.5 kWh", status: .available)
        )
    }

    func test_t_value_unit_mass_scales_to_kilograms() {
        XCTAssertEqual(
            formatter(.mass).format(entity("sensor.m", state: "1500", unit: "g")),
            FormattedEntityValue(text: "1.5 kg", status: .available)
        )
    }

    func test_t_value_unit_mass_scales_to_tonnes() {
        XCTAssertEqual(
            formatter(.mass).format(entity("sensor.m", state: "1500000", unit: "g")),
            FormattedEntityValue(text: "1.5 t", status: .available)
        )
    }

    func test_t_value_unit_scalar_omits_suffix_when_unit_hidden() {
        XCTAssertEqual(
            formatter(.power, showsUnit: false).format(entity("sensor.p", state: "2500", unit: "W")),
            FormattedEntityValue(text: "2.5", status: .available)
        )
    }

    func test_t_value_unit_scalar_non_numeric_passthrough() {
        XCTAssertEqual(
            formatter(.power).format(entity("sensor.p", state: "off", unit: "W")),
            FormattedEntityValue(text: "off", status: .available)
        )
    }

    func test_t_dynamic_icon_battery_levels_at_boundaries() {
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 0.0).symbolName, "battery.0percent")
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 0.2).symbolName, "battery.25percent")
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 0.5).symbolName, "battery.50percent")
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 0.8).symbolName, "battery.75percent")
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 1.0).symbolName, "battery.100percent")
    }

    func test_t_dynamic_icon_battery_accessible_text() {
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 0.5).accessibleText, "battery 50%")
    }

    func test_t_dynamic_icon_signal_levels_at_boundaries() {
        XCTAssertEqual(DynamicIconStyle.signal.icon(for: 0.0).symbolName, "wifi.slash")
        XCTAssertEqual(DynamicIconStyle.signal.icon(for: 0.2).symbolName, "wifi.exclamationmark")
        XCTAssertEqual(DynamicIconStyle.signal.icon(for: 0.5).symbolName, "wifi")
        XCTAssertEqual(DynamicIconStyle.signal.icon(for: 0.8).symbolName, "wifi")
        XCTAssertEqual(DynamicIconStyle.signal.icon(for: 1.0).symbolName, "wifi")
    }

    func test_t_dynamic_icon_sound_levels_at_boundaries() {
        XCTAssertEqual(DynamicIconStyle.sound.icon(for: 0.0).symbolName, "speaker.slash.fill")
        XCTAssertEqual(DynamicIconStyle.sound.icon(for: 0.2).symbolName, "speaker.wave.1.fill")
        XCTAssertEqual(DynamicIconStyle.sound.icon(for: 0.5).symbolName, "speaker.wave.2.fill")
        XCTAssertEqual(DynamicIconStyle.sound.icon(for: 0.8).symbolName, "speaker.wave.3.fill")
        XCTAssertEqual(DynamicIconStyle.sound.icon(for: 1.0).symbolName, "speaker.wave.3.fill")
    }

    func test_t_dynamic_icon_brightness_levels_at_boundaries() {
        XCTAssertEqual(DynamicIconStyle.brightness.icon(for: 0.0).symbolName, "sun.min")
        XCTAssertEqual(DynamicIconStyle.brightness.icon(for: 0.2).symbolName, "sun.min")
        XCTAssertEqual(DynamicIconStyle.brightness.icon(for: 0.5).symbolName, "sun.max")
        XCTAssertEqual(DynamicIconStyle.brightness.icon(for: 0.8).symbolName, "sun.max.fill")
        XCTAssertEqual(DynamicIconStyle.brightness.icon(for: 1.0).symbolName, "sun.max.fill")
    }

    func test_t_dynamic_icon_thermometer_levels_at_boundaries() {
        XCTAssertEqual(DynamicIconStyle.thermometer.icon(for: 0.0).symbolName, "thermometer.low")
        XCTAssertEqual(DynamicIconStyle.thermometer.icon(for: 0.5).symbolName, "thermometer.medium")
        XCTAssertEqual(DynamicIconStyle.thermometer.icon(for: 1.0).symbolName, "thermometer.high")
    }

    func test_t_dynamic_icon_clamps_out_of_range_fractions() {
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: -1.0).symbolName, "battery.0percent")
        XCTAssertEqual(DynamicIconStyle.battery.icon(for: 2.0).symbolName, "battery.100percent")
    }

    func test_t_normalized_fraction_uses_percentage_scale_without_bounds() {
        XCTAssertEqual(NormalizedFraction.resolve(value: 50, minimum: nil, maximum: nil), 0.5)
        XCTAssertEqual(NormalizedFraction.resolve(value: 150, minimum: nil, maximum: nil), 1.0)
        XCTAssertEqual(NormalizedFraction.resolve(value: -10, minimum: nil, maximum: nil), 0.0)
    }

    func test_t_normalized_fraction_rescales_with_bounds() {
        XCTAssertEqual(NormalizedFraction.resolve(value: 500, minimum: 0, maximum: 1000), 0.5)
        XCTAssertEqual(NormalizedFraction.resolve(value: 1500, minimum: 0, maximum: 1000), 1.0)
    }

    func test_t_normalized_fraction_ignores_invalid_bounds() {
        XCTAssertEqual(NormalizedFraction.resolve(value: 50, minimum: 100, maximum: 100), 0.5)
    }

    func test_t_value_unit_battery_icon_maps_value_to_symbol() {
        let value = formatter(.batteryIcon).format(entity("sensor.tank", state: "50", unit: nil), isStale: false)
        XCTAssertEqual(value.iconSymbolName, "battery.50percent")
        XCTAssertEqual(value.text, "battery 50%")
    }

    func test_t_value_unit_battery_icon_uses_bounds() {
        let value = formatter(.batteryIcon, minValue: 0, maxValue: 1000)
            .format(entity("sensor.tank", state: "500", unit: nil))
        XCTAssertEqual(value.iconSymbolName, "battery.50percent")
    }

    func test_t_value_unit_icon_non_numeric_falls_back_to_text() {
        let value = formatter(.signalIcon).format(entity("sensor.x", state: "off", unit: nil))
        XCTAssertNil(value.iconSymbolName)
        XCTAssertEqual(value.text, "off")
    }

    func test_t_value_unit_icon_stale_keeps_symbol() {
        let value = formatter(.batteryIcon).format(entity("sensor.tank", state: "50", unit: nil), isStale: true)
        XCTAssertEqual(value.iconSymbolName, "battery.50percent")
        XCTAssertEqual(value.status, .stale)
        XCTAssertEqual(value.text, "Stale: battery 50%")
    }

    func test_t_value_unit_non_numeric_passthrough_detected() {
        XCTAssertEqual(
            formatter(nil).format(entity("device_tracker.phone", state: "HOME", unit: nil)),
            FormattedEntityValue(text: "HOME", status: .available)
        )
    }

    func test_t_value_unit_non_numeric_passthrough_conversion() {
        XCTAssertEqual(
            formatter(.celsius).format(entity("switch.light", state: "off", unit: nil)),
            FormattedEntityValue(text: "off", status: .available)
        )
    }

    func test_t_value_unit_shows_unit_false_omits_suffix() {
        XCTAssertEqual(
            formatter(.percent, showsUnit: false).format(entity("sensor.h", state: "44", unit: "%")),
            FormattedEntityValue(text: "44", status: .available)
        )
    }

    func test_t_display_defaults_percent_unit_uses_percent() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "%"), .percent)
    }

    func test_t_display_defaults_temperature_unit_matches_scale() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "°F"), .fahrenheit)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "K"), .kelvin)
    }

    func test_t_display_defaults_byte_unit_uses_bytes() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "GiB"), .bytes)
    }

    func test_t_display_defaults_safe_scalar_base_units_are_auto_detected() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "lx"), .illuminance)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "W"), .power)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "Wh"), .energy)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "g"), .mass)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "s"), .duration)
    }

    func test_t_display_defaults_scaled_scalar_units_stay_in_their_family() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "kWh"), .energy)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "kg"), .mass)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "min"), .duration)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "KB/s"), .dataRate)
    }

    func test_t_display_defaults_unknown_unit_uses_number() {
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: "queries"), .number)
        XCTAssertEqual(EntityDisplayDefaults.detectedUnit(haUnit: nil), .number)
    }

    func test_t_display_defaults_effective_unit_prefers_selection() {
        XCTAssertEqual(EntityDisplayDefaults.effectiveUnit(.bytes, haUnit: "%"), .bytes)
        XCTAssertEqual(EntityDisplayDefaults.effectiveUnit(nil, haUnit: "%"), .percent)
    }

    func testEntityDisplayDefaultsApplyHumidityThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.office_humidity",
            name: "Office humidity",
            state: "52",
            unit: "%",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 35, color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)),
                    ThresholdStep(value: 40, color: ValueThresholds.okColor),
                    ThresholdStep(value: 60, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 70, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.warningColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyPM25ThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.queen_pm2_5",
            name: "Queen PM2.5",
            state: "8",
            unit: "µg/m³",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 12, color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)),
                    ThresholdStep(value: 35, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 55, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyPowerThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.deskyuna_power",
            name: "Deskyuna Leistung",
            state: "87.7",
            unit: "W",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 150, color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)),
                    ThresholdStep(value: 500, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 1_200, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyPM10ThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.outdoor_pm10",
            name: "Outdoor PM10",
            state: "18",
            unit: "µg/m³",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 20, color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)),
                    ThresholdStep(value: 45, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 90, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyAQIThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.garden_aqi",
            name: "Garden AQI",
            state: "42",
            unit: nil,
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 51, color: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)),
                    ThresholdStep(value: 101, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 151, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyVOCIndexThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.office_voc_index",
            name: "Office VOC Index",
            state: "84",
            unit: nil,
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 100, color: ValueThresholds.okColor),
                    ThresholdStep(value: 200, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 350, color: ValueThresholds.criticalColor)
                ],
                baseColor: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)
            )
        )
    }

    func testEntityDisplayDefaultsApplyNoiseThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.office_noise",
            name: "Office noise",
            state: "41",
            unit: "dBA",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 35, color: ValueThresholds.okColor),
                    ThresholdStep(value: 55, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 85, color: ValueThresholds.criticalColor)
                ],
                baseColor: PearchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)
            )
        )
    }

    func testEntityDisplayDefaultsApplyStorageUsageThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.nas_disk_usage",
            name: "NAS disk usage",
            state: "72",
            unit: "%",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 80, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 90, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyRadonThresholdScale() {
        let entity = DiscoveredEntity(
            id: "sensor.basement_radon",
            name: "Basement radon",
            state: "62",
            unit: "Bq/m³",
            areaID: nil,
            deviceID: nil
        )

        XCTAssertEqual(
            EntityDisplayDefaults.defaultThresholds(for: entity),
            ValueThresholds(
                steps: [
                    ThresholdStep(value: 75, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 150, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        )
    }

    func testEntityDisplayDefaultsApplyImplicitThresholdsToExistingConfiguration() {
        let entity = DiscoveredEntity(
            id: "sensor.office_temperature",
            name: "Office temperature",
            state: "21.4",
            unit: "°C",
            areaID: nil,
            deviceID: nil
        )

        let effective = EntityDisplayDefaults.effectiveThresholds(
            for: entity,
            configuration: MenuBarItemConfiguration(entityID: entity.id)
        )

        XCTAssertEqual(effective, EntityDisplayDefaults.defaultThresholds(for: entity))
    }

    func test_t_display_defaults_battery_sensor_uses_battery_style() {
        let entity = entity("sensor.phone_battery", name: "Phone battery", state: "82", unit: "%")
        let configuration = EntityDisplayDefaults.configuration(for: entity)

        XCTAssertEqual(configuration.style, .battery)
        XCTAssertNil(configuration.displayUnit)
        XCTAssertEqual(configuration.coverControlMode, .both)
    }

    func test_t_display_defaults_unknown_numeric_sensor_uses_text_style() {
        let entity = entity("sensor.office_power", name: "Office power", state: "120", unit: "W")
        let configuration = EntityDisplayDefaults.configuration(for: entity)

        XCTAssertEqual(configuration.style, .text)
    }

    func test_t_display_defaults_non_percent_battery_name_stays_text() {
        let entity = entity("sensor.battery_voltage", name: "Battery voltage", state: "3.7", unit: "V")
        XCTAssertEqual(EntityDisplayDefaults.defaultStyle(for: entity), .text)
    }

    func testRoomSearchEmptyQueryReturnsEverything() {
        let rooms = searchRooms()
        XCTAssertEqual(PearchHARoomSearch.filter(rooms, query: "   "), rooms)
        XCTAssertEqual(PearchHARoomSearch.filter(rooms, query: ""), rooms)
    }

    func testRoomSearchMatchesRoomNameKeepsAllEntities() {
        let rooms = searchRooms()
        let filtered = PearchHARoomSearch.filter(rooms, query: "off")
        XCTAssertEqual(filtered.map(\.id), ["office"])
        XCTAssertEqual(filtered.first?.entities.map(\.id), ["sensor.office_temp", "sensor.office_humidity"])
    }

    func testRoomSearchMatchesEntityNameKeepsOnlyMatchingEntities() {
        let rooms = searchRooms()
        let filtered = PearchHARoomSearch.filter(rooms, query: "humid")
        XCTAssertEqual(filtered.map(\.id), ["office"])
        XCTAssertEqual(filtered.first?.entities.map(\.id), ["sensor.office_humidity"])
    }

    func testRoomSearchDropsRoomsWithNoMatch() {
        let rooms = searchRooms()
        XCTAssertTrue(PearchHARoomSearch.filter(rooms, query: "zzz").isEmpty)
    }

    func testHistoryCursorNearestSampleEdgesAndMidpoints() {
        let series = cursorSeries()
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 0)?.value, 10)
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 1)?.value, 30)
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 0.5)?.value, 20)
    }

    func testHistoryCursorClampsOutOfRangeX() {
        let series = cursorSeries()
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: -5)?.value, 10)
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 5)?.value, 30)
    }

    func testHistoryCursorReturnsNilWhenNoNumericSamples() {
        let series = HistorySeries(
            entityID: "sensor.office_temp",
            range: .day,
            samples: [HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "off", numericValue: nil)]
        )
        XCTAssertNil(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 0.5))
    }

    func testHistoryCursorSingleSampleIgnoresPosition() {
        let series = HistorySeries(
            entityID: "sensor.office_temp",
            range: .day,
            samples: [HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "10", numericValue: 10)]
        )
        XCTAssertEqual(PearchHAHistoryCursor.nearestSample(in: series, atNormalizedX: 0.9)?.value, 10)
    }

    private func cursorSeries() -> HistorySeries {
        HistorySeries(
            entityID: "sensor.office_temp",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "10", numericValue: 10),
                HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "20", numericValue: 20),
                HistorySample(timestamp: Date(timeIntervalSince1970: 200), state: "30", numericValue: 30)
            ]
        )
    }

    private func searchRooms() -> [Room] {
        [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    entity("sensor.office_temp", name: "Temperature", state: "21", unit: "°C"),
                    entity("sensor.office_humidity", name: "Humidity", state: "44", unit: "%")
                ]
            ),
            Room(
                id: "kitchen",
                name: "Kitchen",
                entities: [
                    entity("sensor.kitchen_power", name: "Power", state: "120", unit: "W")
                ]
            )
        ]
    }

    private func entity(_ id: EntityID, name: String? = nil, state: String, unit: String?) -> DiscoveredEntity {
        DiscoveredEntity(
            id: id,
            name: name ?? id.rawValue,
            state: state,
            unit: unit,
            areaID: nil,
            deviceID: nil
        )
    }

    // MARK: - History state segments

    func testHistoryStateSegmentsMergesConsecutiveEqualStates() {
        let series = HistorySeries(
            entityID: "cover.blinds",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "open", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 100), state: "open", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 300), state: "closed", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 600), state: "closed", numericValue: nil)
            ]
        )
        let segments = HistoryStateSegments.segments(of: series)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].state, "open")
        XCTAssertEqual(segments[0].start, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(segments[0].end, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(segments[0].duration, 300)
        XCTAssertEqual(segments[1].state, "closed")
        XCTAssertEqual(segments[1].start, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(segments[1].end, Date(timeIntervalSince1970: 600))
        XCTAssertEqual(segments[1].duration, 300)
    }

    func testHistoryStateSegmentsSortsOutOfOrderSamplesByTimestamp() {
        let series = HistorySeries(
            entityID: "switch.lamp",
            range: .day,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 300), state: "off", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 0), state: "on", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 150), state: "on", numericValue: nil)
            ]
        )
        let segments = HistoryStateSegments.segments(of: series)
        XCTAssertEqual(segments.map(\.state), ["on", "off"])
        XCTAssertEqual(segments[0].duration, 300)
    }

    func testHistoryStateSegmentsSingleSampleIsOneZeroDurationSegment() {
        let series = HistorySeries(
            entityID: "binary_sensor.door",
            range: .hour,
            samples: [HistorySample(timestamp: Date(timeIntervalSince1970: 42), state: "on", numericValue: nil)]
        )
        let segments = HistoryStateSegments.segments(of: series)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].state, "on")
        XCTAssertEqual(segments[0].start, segments[0].end)
        XCTAssertEqual(segments[0].duration, 0)
    }

    func testHistoryStateSegmentsEmptySeriesYieldsNoSegments() {
        let series = HistorySeries(entityID: "switch.lamp", range: .day, samples: [])
        XCTAssertTrue(HistoryStateSegments.segments(of: series).isEmpty)
    }

    func testHistoryStateColorKindClassifiesCommonStates() {
        XCTAssertEqual(HistoryStateColorKind.classify("on"), .active)
        XCTAssertEqual(HistoryStateColorKind.classify(" OPEN "), .active)
        XCTAssertEqual(HistoryStateColorKind.classify("home"), .active)
        XCTAssertEqual(HistoryStateColorKind.classify("off"), .inactive)
        XCTAssertEqual(HistoryStateColorKind.classify("Closed"), .inactive)
        XCTAssertEqual(HistoryStateColorKind.classify("away"), .inactive)
    }

    func testHistoryStateColorKindHashesUnknownStatesIntoStablePaletteSlots() {
        let first = HistoryStateColorKind.classify("heating_cooldown")
        let second = HistoryStateColorKind.classify("heating_cooldown")
        XCTAssertEqual(first, second)
        guard case let .palette(slot) = first else {
            return XCTFail("expected palette slot for unmapped state")
        }
        XCTAssertTrue((0..<HistoryStateColorKind.paletteSlotCount).contains(slot))
    }

    // MARK: - Entity row presentation

    func testEntityRowPresentationUsesGaugeForPercentUnit() {
        let presentation = PearchHAEntityRowPresentation.resolve(
            entity: entity("sensor.humidity", state: "44", unit: "%"),
            configuration: MenuBarItemConfiguration(entityID: "sensor.humidity")
        )
        guard case let .gauge(gauge) = presentation else {
            return XCTFail("expected gauge for percent unit")
        }
        XCTAssertEqual(gauge.fraction, 0.44, accuracy: 0.0001)
        XCTAssertEqual(gauge.severity, .normal)
        XCTAssertEqual(gauge.style, .ring)
    }

    func testEntityRowPresentationGaugeUsesConfiguredStyleAndTotal() {
        let presentation = PearchHAEntityRowPresentation.resolve(
            entity: entity("sensor.tank", state: "75", unit: "L"),
            configuration: MenuBarItemConfiguration(entityID: "sensor.tank", style: .battery, absoluteTotal: 150)
        )
        guard case let .gauge(gauge) = presentation else {
            return XCTFail("expected gauge for value with absolute total")
        }
        XCTAssertEqual(gauge.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gauge.style, .battery)
    }

    func testEntityRowPresentationGaugeSeverityFollowsThresholds() {
        let presentation = PearchHAEntityRowPresentation.resolve(
            entity: entity("sensor.cpu", state: "95", unit: "%"),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.cpu",
                thresholds: ValueThresholds(warning: nil, critical: ValueThreshold(value: 90, direction: .aboveOrEqual))
            )
        )
        guard case let .gauge(gauge) = presentation else {
            return XCTFail("expected gauge")
        }
        XCTAssertEqual(gauge.severity, .critical)
    }

    func testEntityRowPresentationUsesStatePillForOnOff() {
        XCTAssertEqual(
            PearchHAEntityRowPresentation.resolve(
                entity: entity("switch.lamp", state: "on", unit: nil),
                configuration: MenuBarItemConfiguration(entityID: "switch.lamp")
            ),
            .statePill(isActive: true)
        )
        XCTAssertEqual(
            PearchHAEntityRowPresentation.resolve(
                entity: entity("cover.blinds", state: "closed", unit: nil),
                configuration: MenuBarItemConfiguration(entityID: "cover.blinds")
            ),
            .statePill(isActive: false)
        )
    }

    func testEntityRowPresentationUsesGaugeForConfiguredBoundsAlone() {
        let presentation = PearchHAEntityRowPresentation.resolve(
            entity: entity("sensor.tank", state: "500", unit: "L"),
            configuration: MenuBarItemConfiguration(entityID: "sensor.tank")
                .settingBounds(minValue: 0, maxValue: 1000)
        )
        guard case let .gauge(gauge) = presentation else {
            return XCTFail("expected gauge resolved from configured min/max bounds alone")
        }
        XCTAssertEqual(gauge.fraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(gauge.severity, .normal)
        XCTAssertEqual(gauge.style, .ring)
    }

    func testEntityRowPresentationUsesPlainValueWhenNoFractionOrState() {
        XCTAssertEqual(
            PearchHAEntityRowPresentation.resolve(
                entity: entity("sensor.power", state: "120", unit: "W"),
                configuration: MenuBarItemConfiguration(entityID: "sensor.power")
            ),
            .value(severity: .normal)
        )
    }
}
#endif

extension PearchHACoreTests {
    func test_t_threshold_steps_apply_highest_step_at_or_below_the_value() {
        let thresholds = ValueThresholds(
            steps: [
                ThresholdStep(value: 90, color: ValueThresholds.criticalColor),
                ThresholdStep(value: 70, color: ValueThresholds.warningColor)
            ],
            baseColor: ValueThresholds.okColor
        )

        XCTAssertEqual(thresholds.color(for: 95), ValueThresholds.criticalColor)
        XCTAssertEqual(thresholds.color(for: 90), ValueThresholds.criticalColor, "steps are inclusive at their edge")
        XCTAssertEqual(thresholds.color(for: 89), ValueThresholds.warningColor)
        XCTAssertEqual(thresholds.color(for: 10), ValueThresholds.okColor, "below every step the base applies")

        XCTAssertEqual(thresholds.severity(for: 95), .critical)
        XCTAssertEqual(thresholds.severity(for: 89), .warning)
        XCTAssertEqual(thresholds.severity(for: 10), .normal)
    }

    func test_t_threshold_without_base_or_matching_step_is_normal() {
        let thresholds = ValueThresholds(steps: [ThresholdStep(value: 50, color: ValueThresholds.criticalColor)])
        XCTAssertNil(thresholds.color(for: 10))
        XCTAssertEqual(thresholds.severity(for: 10), .normal)
    }

    func test_t_threshold_severity_heuristic_classifies_custom_colors() {
        XCTAssertEqual(ValueThresholds.severity(of: PearchHAAccentColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)), .critical)
        XCTAssertEqual(ValueThresholds.severity(of: PearchHAAccentColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1)), .warning)
        XCTAssertEqual(ValueThresholds.severity(of: PearchHAAccentColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)), .normal)
    }

    func test_t_state_threshold_rules_match_case_insensitively() {
        let thresholds = StateThresholds(
            rules: [
                StateThresholdRule(match: "GOOD", color: ValueThresholds.okColor),
                StateThresholdRule(match: "bad", color: ValueThresholds.criticalColor)
            ],
            baseColor: ValueThresholds.warningColor
        )

        XCTAssertEqual(thresholds.color(for: " good "), ValueThresholds.okColor)
        XCTAssertEqual(thresholds.severity(for: "BAD"), .critical)
        XCTAssertEqual(thresholds.severity(for: "Very Bad Air"), .critical)
        XCTAssertEqual(thresholds.color(for: "unknown"), ValueThresholds.warningColor)
    }

    func test_t_state_threshold_rules_prefer_longest_matching_rule() {
        let progressColor = PearchHAAccentColor(red: 0.19, green: 0.49, blue: 0.96, alpha: 1)
        let thresholds = StateThresholds(
            rules: [
                StateThresholdRule(match: "OPEN", color: ValueThresholds.okColor),
                StateThresholdRule(match: "OPENING", color: progressColor)
            ]
        )

        XCTAssertEqual(thresholds.color(for: "opening"), progressColor)
    }

    func test_t_default_state_thresholds_choose_good_medium_bad_family_for_matching_text_state() {
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("sensor.air_quality", name: "Air quality", state: "Very Bad Air", unit: nil)
        )

        XCTAssertEqual(thresholds.color(for: "GOOD"), ValueThresholds.okColor)
        XCTAssertEqual(thresholds.color(for: "MEDIUM"), ValueThresholds.warningColor)
        XCTAssertEqual(thresholds.color(for: "BAD"), ValueThresholds.criticalColor)
        XCTAssertEqual(thresholds.severity(for: "Very Bad Air"), .critical)
    }

    func test_t_default_state_thresholds_choose_complete_on_off_family() {
        let neutralColor = PearchHAAccentColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("switch.office_fan", name: "Office fan", state: "off", unit: nil)
        )

        XCTAssertEqual(thresholds.color(for: "on"), ValueThresholds.okColor)
        XCTAssertEqual(thresholds.color(for: "off"), neutralColor)
    }

    func test_t_default_state_thresholds_choose_cover_family_for_opening_state() {
        let progressColor = PearchHAAccentColor(red: 0.19, green: 0.49, blue: 0.96, alpha: 1)
        let neutralColor = PearchHAAccentColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("cover.office_blinds", name: "Office blinds", state: "opening", unit: nil)
        )

        XCTAssertEqual(thresholds.color(for: "opening"), progressColor)
        XCTAssertEqual(thresholds.color(for: "open"), ValueThresholds.okColor)
        XCTAssertEqual(thresholds.color(for: "closed"), neutralColor)
    }

    func test_t_default_state_thresholds_choose_domain_specific_update_family() {
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("update.router_firmware", name: "Router firmware", state: "on", unit: nil)
        )

        XCTAssertEqual(thresholds.color(for: "on"), ValueThresholds.warningColor)
        XCTAssertEqual(thresholds.color(for: "off"), ValueThresholds.okColor)
    }

    func test_t_default_state_thresholds_choose_vacuum_family() {
        let progressColor = PearchHAAccentColor(red: 0.19, green: 0.49, blue: 0.96, alpha: 1)
        let neutralColor = PearchHAAccentColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1)
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("vacuum.living_room", name: "Living room vacuum", state: "paused", unit: nil)
        )

        XCTAssertEqual(thresholds.color(for: "cleaning"), progressColor)
        XCTAssertEqual(thresholds.color(for: "docked"), ValueThresholds.okColor)
        XCTAssertEqual(thresholds.color(for: "idle"), neutralColor)
        XCTAssertEqual(thresholds.color(for: "error"), ValueThresholds.criticalColor)
        XCTAssertEqual(thresholds.color(for: "paused"), ValueThresholds.warningColor)
    }

    func test_t_default_state_thresholds_ignore_numeric_values() {
        let thresholds = EntityDisplayDefaults.defaultStateThresholds(
            for: entity("sensor.temperature", name: "Temperature", state: "21.4", unit: "°C")
        )

        XCTAssertFalse(EntityDisplayDefaults.hasStateThresholds(thresholds))
        XCTAssertTrue(thresholds.rules.isEmpty)
    }

    func test_t_effective_state_thresholds_use_defaults_until_user_overrides() {
        let entity = entity("sensor.air_quality", name: "Air quality", state: "GOOD", unit: nil)
        let inherited = EntityDisplayDefaults.effectiveStateThresholds(
            for: entity,
            configuration: EntityDisplayDefaults.configuration(for: entity)
        )

        XCTAssertEqual(inherited.color(for: "GOOD"), ValueThresholds.okColor)
        XCTAssertEqual(inherited.severity(for: "BAD"), .critical)

        let overridden = EntityDisplayDefaults.effectiveStateThresholds(
            for: entity,
            configuration: EntityDisplayDefaults.configuration(for: entity).settingStateThresholds(
                StateThresholds(
                    rules: [StateThresholdRule(match: "GOOD", color: ValueThresholds.criticalColor)]
                )
            )
        )

        XCTAssertEqual(overridden.color(for: "GOOD"), ValueThresholds.criticalColor)
        XCTAssertNil(overridden.color(for: "BAD"))
    }

    func test_t_dashboard_room_row_cap_defaults_to_six() {
        XCTAssertEqual(PearchHADisplayPreferences.defaults.dashboardRoomRowCap, 6)
    }

    func test_t_dashboard_room_row_cap_uses_configured_positive_limit() {
        XCTAssertEqual(
            PearchHADisplayPreferences.defaults.with(dashboardRoomRowLimit: 3).dashboardRoomRowCap,
            3
        )
    }

    func test_t_dashboard_room_row_cap_negative_means_no_limit() {
        XCTAssertNil(PearchHADisplayPreferences.defaults.with(dashboardRoomRowLimit: -1).dashboardRoomRowCap)
    }
}

#if canImport(XCTest)
// MARK: - Diagnostics log and retry/backoff summaries

extension PearchHACoreTests {
    private func instant(_ seconds: Int64) -> PearchInstant {
        PearchInstant(nanosecondsSinceStart: seconds * 1_000_000_000)
    }

    func test_t_diagnostic_event_kinds_carry_calm_system_images() {
        XCTAssertEqual(PearchHADiagnosticEventKind.connectionFailed.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(PearchHADiagnosticEventKind.reconnecting.systemImage, "arrow.triangle.2.circlepath")
        XCTAssertEqual(PearchHADiagnosticEventKind.recovered.systemImage, "checkmark.circle.fill")
        XCTAssertEqual(PearchHADiagnosticEventKind.refreshFailed.systemImage, "arrow.clockwise.circle")
        XCTAssertEqual(PearchHADiagnosticEventKind.liveUpdatesInterrupted.systemImage, "dot.radiowaves.left.and.right")
    }

    func test_t_diagnostic_log_records_first_event_with_matching_instants() throws {
        var log = PearchHADiagnosticLog()
        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(log.count, 0)

        log.record(kind: .connectionFailed, message: "authentication failed", now: instant(1))

        XCTAssertFalse(log.isEmpty)
        XCTAssertEqual(log.count, 1)
        let event = try XCTUnwrap(log.oldestFirst.first)
        XCTAssertEqual(event.kind, .connectionFailed)
        XCTAssertEqual(event.message, "authentication failed")
        XCTAssertEqual(event.firstSeen, instant(1))
        XCTAssertEqual(event.lastSeen, instant(1))
        XCTAssertEqual(event.count, 1)
    }

    func test_t_diagnostic_log_collapses_consecutive_identical_events() throws {
        var log = PearchHADiagnosticLog()
        log.record(kind: .refreshFailed, message: "host unreachable", now: instant(1))
        let originalID = try XCTUnwrap(log.oldestFirst.first).id

        log.record(kind: .refreshFailed, message: "host unreachable", now: instant(5))

        XCTAssertEqual(log.count, 1)
        let collapsed = try XCTUnwrap(log.oldestFirst.first)
        XCTAssertEqual(collapsed.id, originalID)
        XCTAssertEqual(collapsed.count, 2)
        XCTAssertEqual(collapsed.firstSeen, instant(1))
        XCTAssertEqual(collapsed.lastSeen, instant(5))
    }

    func test_t_diagnostic_log_appends_distinct_events_and_orders_both_directions() {
        var log = PearchHADiagnosticLog()
        log.record(kind: .refreshFailed, message: "host unreachable", now: instant(1))
        log.record(kind: .refreshFailed, message: "timeout", now: instant(2))
        log.record(kind: .recovered, message: "timeout", now: instant(3))

        XCTAssertEqual(log.count, 3)
        XCTAssertEqual(log.oldestFirst.map(\.message), ["host unreachable", "timeout", "timeout"])
        XCTAssertEqual(log.oldestFirst.map(\.kind), [.refreshFailed, .refreshFailed, .recovered])
        XCTAssertEqual(log.newestFirst.map(\.kind), [.recovered, .refreshFailed, .refreshFailed])
    }

    func test_t_diagnostic_log_evicts_oldest_event_beyond_capacity() {
        var log = PearchHADiagnosticLog(capacity: 2)
        log.record(kind: .connectionFailed, message: "first", now: instant(1))
        log.record(kind: .connectionFailed, message: "second", now: instant(2))
        log.record(kind: .connectionFailed, message: "third", now: instant(3))

        XCTAssertEqual(log.count, 2)
        XCTAssertEqual(log.oldestFirst.map(\.message), ["second", "third"])
    }

    func test_t_diagnostic_log_clear_empties_buffer() {
        var log = PearchHADiagnosticLog()
        log.record(kind: .reconnecting, message: "attempt 1", now: instant(1))

        log.clear()

        XCTAssertTrue(log.isEmpty)
        XCTAssertEqual(log.count, 0)
        XCTAssertEqual(log.oldestFirst, [])
        XCTAssertEqual(log.newestFirst, [])
    }

    func test_t_diagnostic_log_init_clamps_capacity_and_keeps_newest_seed_events() {
        let older = PearchHADiagnosticEvent(
            kind: .connectionFailed,
            message: "older",
            firstSeen: instant(1),
            lastSeen: instant(1)
        )
        let newer = PearchHADiagnosticEvent(
            kind: .recovered,
            message: "newer",
            firstSeen: instant(2),
            lastSeen: instant(2)
        )

        let log = PearchHADiagnosticLog(capacity: 0, events: [older, newer])

        XCTAssertEqual(log.capacity, 1)
        XCTAssertEqual(log.oldestFirst.map(\.message), ["newer"])
    }

    func test_t_diagnostic_event_clamps_non_positive_count_to_one() {
        let event = PearchHADiagnosticEvent(
            kind: .recovered,
            message: "back",
            firstSeen: instant(1),
            lastSeen: instant(1),
            count: 0
        )
        XCTAssertEqual(event.count, 1)
    }

    func test_t_retry_backoff_summary_connected() {
        XCTAssertEqual(PearchHARetryBackoffState.connected.summary, "Connected")
    }

    func test_t_retry_backoff_summary_connecting() {
        XCTAssertEqual(PearchHARetryBackoffState.connecting.summary, "Connecting")
    }

    func test_t_retry_backoff_summary_reconnecting_names_the_attempt() {
        XCTAssertEqual(PearchHARetryBackoffState.reconnecting(attempt: 3).summary, "Reconnecting, attempt 3")
    }

    func test_t_retry_backoff_summary_single_failure_omits_streak() {
        XCTAssertEqual(
            PearchHARetryBackoffState.backingOff(failureStreak: 1, nextRetrySeconds: 30).summary,
            "Backing off, next retry in 30 s"
        )
    }

    func test_t_retry_backoff_summary_repeated_failures_name_the_streak() {
        XCTAssertEqual(
            PearchHARetryBackoffState.backingOff(failureStreak: 4, nextRetrySeconds: 120).summary,
            "Backing off (4 failures), next retry in 120 s"
        )
    }

    func test_t_retry_backoff_summary_disconnected() {
        XCTAssertEqual(PearchHARetryBackoffState.disconnected.summary, "Disconnected")
    }
}

// MARK: - Appearance preference labels

extension PearchHACoreTests {
    func test_t_menu_bar_appearance_display_names() {
        XCTAssertEqual(PearchHAMenuBarAppearance.iconAndText.displayName, "Icon and text")
        XCTAssertEqual(PearchHAMenuBarAppearance.iconOnly.displayName, "Icon only")
        XCTAssertEqual(PearchHAMenuBarAppearance.textOnly.displayName, "Text only")
    }

    func test_t_theme_mode_display_names() {
        XCTAssertEqual(PearchHAThemeMode.system.displayName, "System")
        XCTAssertEqual(PearchHAThemeMode.light.displayName, "Light")
        XCTAssertEqual(PearchHAThemeMode.dark.displayName, "Dark")
    }

    func test_t_dashboard_row_density_display_names() {
        XCTAssertEqual(PearchHADashboardRowDensity.comfortable.displayName, "Comfortable")
        XCTAssertEqual(PearchHADashboardRowDensity.compact.displayName, "Compact")
    }
}

// MARK: - Core identifiers, actions, and service labels

extension PearchHACoreTests {
    func test_t_area_and_device_ids_round_trip_as_json_strings() throws {
        let areaData = try JSONEncoder().encode([AreaID("kitchen")])
        XCTAssertEqual(String(data: areaData, encoding: .utf8), #"["kitchen"]"#)
        XCTAssertEqual(try JSONDecoder().decode([AreaID].self, from: areaData), [AreaID("kitchen")])

        let deviceData = try JSONEncoder().encode([DeviceID("thermostat")])
        XCTAssertEqual(String(data: deviceData, encoding: .utf8), #"["thermostat"]"#)
        XCTAssertEqual(try JSONDecoder().decode([DeviceID].self, from: deviceData), [DeviceID("thermostat")])
    }

    func test_t_action_value_exposes_protected_reference_only_for_protected_strings() {
        XCTAssertEqual(ActionValue.protectedString("pin-ref").protectedValueReference, "pin-ref")
        XCTAssertNil(ActionValue.string("1234").protectedValueReference)
        XCTAssertNil(ActionValue.number(4).protectedValueReference)
    }

    func test_t_custom_action_is_runnable_reflects_validation() {
        let complete = EntityCustomAction(
            id: "run-scene",
            entityID: "light.office",
            title: "Movie scene",
            action: ActionSpec(domain: "scene", service: "turn_on", targetEntityID: "scene.movie")
        )
        let incomplete = EntityCustomAction(
            id: "blank-title",
            entityID: "light.office",
            title: "   ",
            action: ActionSpec(domain: "scene", service: "turn_on", targetEntityID: nil)
        )

        XCTAssertTrue(complete.isRunnable)
        XCTAssertFalse(incomplete.isRunnable)
    }

    func test_t_service_label_domain_title_capitalizes_each_word() {
        XCTAssertEqual(PearchHAServiceLabel.domainTitle("media_player"), "Media Player")
        XCTAssertEqual(PearchHAServiceLabel.domainTitle(""), "")
    }

    func test_t_service_label_service_title_capitalizes_first_word_only() {
        XCTAssertEqual(PearchHAServiceLabel.serviceTitle("turn_on"), "Turn on")
        XCTAssertEqual(PearchHAServiceLabel.serviceTitle("   "), "")
    }

    func test_t_service_label_friendly_label_combines_available_parts() {
        XCTAssertEqual(PearchHAServiceLabel.friendlyLabel(domain: "script", service: "turn_on"), "Script: Turn on")
        XCTAssertEqual(PearchHAServiceLabel.friendlyLabel(domain: "script", service: ""), "Script")
        XCTAssertEqual(PearchHAServiceLabel.friendlyLabel(domain: "", service: "turn_on"), "Turn on")
        XCTAssertEqual(PearchHAServiceLabel.friendlyLabel(domain: "", service: ""), "")
    }

    func test_t_room_resolver_names_unlisted_area_by_its_raw_id() {
        let rooms = RoomResolver().resolve(
            snapshot: DiscoverySnapshot(
                areas: [],
                devices: [],
                entities: [
                    EntityRegistryEntry(id: "sensor.attic_temp", name: "Attic temp", areaID: "attic", deviceID: nil)
                ],
                states: [
                    EntityState(id: "sensor.attic_temp", name: "Fallback", state: "18", unit: "°C")
                ]
            )
        )

        XCTAssertEqual(rooms.map(\.id), [RoomID("attic")])
        XCTAssertEqual(rooms.map(\.name), ["attic"])
        XCTAssertEqual(rooms.first?.entities.map(\.id), ["sensor.attic_temp"])
    }
}

// MARK: - Threshold and menu-bar configuration behavior

extension PearchHACoreTests {
    func test_t_value_threshold_matches_directions_inclusively() {
        let above = ValueThreshold(value: 90, direction: .aboveOrEqual)
        XCTAssertTrue(above.matches(90))
        XCTAssertTrue(above.matches(95))
        XCTAssertFalse(above.matches(89))

        let below = ValueThreshold(value: 15, direction: .belowOrEqual)
        XCTAssertTrue(below.matches(15))
        XCTAssertTrue(below.matches(10))
        XCTAssertFalse(below.matches(16))
    }

    func test_t_below_or_equal_setter_inverts_into_base_color() {
        let thresholds = ValueThresholds().replacingThresholdRule(
            color: ValueThresholds.warningColor,
            threshold: ValueThreshold(value: 20, direction: .belowOrEqual)
        )

        XCTAssertEqual(thresholds.baseColor, ValueThresholds.warningColor)
        XCTAssertEqual(thresholds.color(for: 10), ValueThresholds.warningColor)
        XCTAssertEqual(thresholds.severity(for: 20), .warning)
        XCTAssertEqual(thresholds.severity(for: 50), .normal)
    }

    func test_t_menu_bar_display_configuration_reports_promotion() {
        let configuration = MenuBarDisplayConfiguration(promotedEntityIDs: ["sensor.cpu"])

        XCTAssertTrue(configuration.isPromoted("sensor.cpu"))
        XCTAssertFalse(configuration.isPromoted("sensor.memory"))
    }

    func test_t_menu_bar_promotion_boundary_moves_are_no_ops() {
        let configuration = MenuBarDisplayConfiguration(promotedEntityIDs: ["sensor.first", "sensor.last"])

        XCTAssertEqual(
            configuration.movingPromotion("sensor.first", direction: .up),
            configuration
        )
        XCTAssertEqual(
            configuration.movingPromotion("sensor.last", direction: .down),
            configuration
        )
    }

    func test_t_menu_bar_renderer_treats_blank_units_as_compatible_for_total_entity() {
        let rendered = MenuBarItemRenderer().render(
            entity: DiscoveredEntity(id: "sensor.used", name: "Used", state: "30", unit: "  ", areaID: nil, deviceID: nil),
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.used",
                style: .ring,
                totalEntityID: "sensor.total"
            ),
            availableEntities: [
                DiscoveredEntity(id: "sensor.total", name: "Total", state: "120", unit: "", areaID: nil, deviceID: nil)
            ],
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(rendered.title, "RING 25%")
        XCTAssertEqual(rendered.gauge, MenuBarGauge(percent: 25, filledSegments: 3, segmentCount: 10))
    }
}

// MARK: - Value unit metadata and non-numeric fallbacks

extension PearchHACoreTests {
    func test_t_value_unit_display_names() {
        let expected: [ValueUnit: String] = [
            .number: "Number",
            .compact: "Compact (SI)",
            .percent: "Percent",
            .celsius: "Celsius",
            .fahrenheit: "Fahrenheit",
            .kelvin: "Kelvin",
            .bytes: "Bytes",
            .dataRate: "Data rate",
            .illuminance: "Illuminance (lx)",
            .power: "Power (W)",
            .energy: "Energy (Wh)",
            .mass: "Mass (g)",
            .duration: "Duration",
            .batteryIcon: "Battery icon",
            .signalIcon: "Signal icon",
            .soundIcon: "Sound icon",
            .brightnessIcon: "Brightness icon",
            .thermometerIcon: "Thermometer icon"
        ]
        for unit in ValueUnit.allCases {
            XCTAssertEqual(unit.displayName, expected[unit], "displayName for \(unit.rawValue)")
        }
    }

    func test_t_value_unit_normalized_fraction_applies_to_percent_and_icon_units() {
        XCTAssertTrue(ValueUnit.percent.usesNormalizedFraction)
        XCTAssertTrue(ValueUnit.batteryIcon.usesNormalizedFraction)
        XCTAssertTrue(ValueUnit.signalIcon.usesNormalizedFraction)
        XCTAssertFalse(ValueUnit.number.usesNormalizedFraction)
        XCTAssertFalse(ValueUnit.bytes.usesNormalizedFraction)
    }

    func test_t_temperature_unit_recognition() {
        XCTAssertTrue(TemperatureConversion.isTemperatureUnit("°C"))
        XCTAssertTrue(TemperatureConversion.isTemperatureUnit("Fahrenheit"))
        XCTAssertTrue(TemperatureConversion.isTemperatureUnit("K"))
        XCTAssertFalse(TemperatureConversion.isTemperatureUnit("lx"))
        XCTAssertNil(TemperatureConversion.scale(of: nil))
        XCTAssertNil(TemperatureConversion.scale(of: "   "))
    }

    func test_t_value_unit_non_numeric_state_passes_through_for_every_converting_unit() {
        let convertingUnits: [ValueUnit] = [
            .compact, .percent, .bytes, .dataRate, .illuminance, .power, .energy, .mass, .duration
        ]
        for unit in convertingUnits {
            XCTAssertEqual(
                formatter(unit).format(entity("sensor.mode", state: "idle", unit: nil)),
                FormattedEntityValue(text: "idle", status: .available),
                "non-numeric passthrough for \(unit.rawValue)"
            )
        }
    }

    func test_t_value_unit_number_auto_scales_power_family_using_reported_unit() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.power", state: "1530", unit: "W")),
            FormattedEntityValue(text: "1.53 kW", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.energy", state: "1500", unit: "kWh")),
            FormattedEntityValue(text: "1.5 MWh", status: .available)
        )
    }

    func test_t_value_unit_number_auto_scales_common_ha_measurement_families() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.current", state: "2500", unit: "mA")),
            FormattedEntityValue(text: "2.5 A", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.voltage", state: "2500", unit: "mV")),
            FormattedEntityValue(text: "2.5 V", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.frequency", state: "2500", unit: "Hz")),
            FormattedEntityValue(text: "2.5 kHz", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.pressure", state: "1013", unit: "hPa")),
            FormattedEntityValue(text: "101.3 kPa", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.uptime", state: "90", unit: "min")),
            FormattedEntityValue(text: "90 min", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.pm", state: "1500", unit: "µg/m³")),
            FormattedEntityValue(text: "1.5 mg/m³", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.storage", state: "1536", unit: "MB")),
            FormattedEntityValue(text: "1.5 GB", status: .available)
        )
    }

    func test_t_value_unit_number_auto_scales_down_to_smaller_measurement_units() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.current", state: "0.3", unit: "A")),
            FormattedEntityValue(text: "300 mA", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.volume", state: "0.5", unit: "L")),
            FormattedEntityValue(text: "500 mL", status: .available)
        )
    }

    func test_t_value_unit_explicit_symbol_overrides_auto_scaling_target() {
        let formatter = EntityValueFormatter(
            locale: Locale(identifier: "en_US"),
            maximumFractionDigits: 1,
            displayUnit: .power,
            displayUnitSymbol: "W"
        )
        XCTAssertEqual(
            formatter.format(entity("sensor.power", state: "1.53", unit: "kW")),
            FormattedEntityValue(text: "1530 W", status: .available)
        )
    }

    func test_t_value_unit_number_preserves_reported_unit_for_zero_values() {
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.current", state: "0", unit: "A")),
            FormattedEntityValue(text: "0 A", status: .available)
        )
        XCTAssertEqual(
            formatter(.number).format(entity("sensor.power", state: "0", unit: "W")),
            FormattedEntityValue(text: "0 W", status: .available)
        )
    }

    func test_t_value_unit_illuminance_trims_trailing_decimal_point() {
        XCTAssertEqual(
            formatter(.illuminance).format(entity("sensor.lux", state: "0.001", unit: "lx")),
            FormattedEntityValue(text: "0 lx", status: .available)
        )
    }
}

// MARK: - Selection reorderer no-op guards

extension PearchHACoreTests {
    private func explicitSelectionConfiguration() -> EntitySelectionConfiguration {
        EntitySelectionConfiguration(
            selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
            roomOrder: ["office", "kitchen"],
            entityOrder: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
            isExplicit: true
        )
    }

    func test_t_selection_reorderer_room_drop_to_same_position_keeps_configuration() {
        let original = explicitSelectionConfiguration()

        let configuration = EntitySelectionReorderer().moveRoom(
            "office",
            relativeTo: "kitchen",
            placement: .before,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func test_t_selection_reorderer_entity_move_up_at_top_keeps_configuration() {
        let original = explicitSelectionConfiguration()

        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_temperature",
            direction: .up,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func test_t_selection_reorderer_entity_move_down_at_bottom_keeps_configuration() {
        let original = explicitSelectionConfiguration()

        let configuration = EntitySelectionReorderer().moveEntity(
            "switch.kitchen_light",
            direction: .down,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func test_t_selection_reorderer_entity_drop_onto_itself_keeps_configuration() {
        let original = explicitSelectionConfiguration()

        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_temperature",
            relativeTo: "sensor.office_temperature",
            placement: .after,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }

    func test_t_selection_reorderer_entity_drop_to_same_position_keeps_configuration() {
        let original = explicitSelectionConfiguration()

        let configuration = EntitySelectionReorderer().moveEntity(
            "sensor.office_temperature",
            relativeTo: "sensor.office_humidity",
            placement: .before,
            rooms: selectionRooms(),
            configuration: original
        )

        XCTAssertEqual(configuration, original)
    }
}
#endif
