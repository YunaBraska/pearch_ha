#if canImport(XCTest)
import XCTest
import PerchHACore

final class PerchHACoreTests: XCTestCase {
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

        XCTAssertTrue(text.contains(#""$perchha":"protected_string""#))
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
                    Device(id: "air_sensor", name: "Air sensor", areaID: "office")
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
        XCTAssertEqual(rendered.accessibilityLabel, "Office humidity, 44 %, 44 percent, battery")
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
        XCTAssertEqual(rendered.accessibilityLabel, "Battery, 15 %, 15 percent, critical, battery")
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
        XCTAssertNil(cleared.thresholds.warning)
        XCTAssertNil(cleared.thresholds.critical)
        XCTAssertEqual(cleared.defaultHistoryRange, .day)

        XCTAssertEqual(cleared.updating(defaultHistoryRange: .month).defaultHistoryRange, .month)
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
}
#endif
