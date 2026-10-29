---
layout: default
help: true
title: PearchHA help
description: Connect Home Assistant to a focused macOS menu bar app.
---

# PearchHA help

PearchHA puts the rooms, values and controls you use most in the macOS menu bar. It connects to your own Home Assistant instance and keeps the session in the Keychain.

## Connect your home

On first launch, enter the address of your Home Assistant instance and sign in in the browser window. PearchHA returns to the app after the approval and restores the secure session from the Keychain later.

![First connection to Home Assistant]({{ '/assets/help/first-run.png' | relative_url }})

Your Home Assistant instance must be reachable from the Mac. If an address changes, update it in the app settings before reconnecting.

## Menu bar and rooms

<a id="menu-bar"></a>

Choose the values, gauges and entities you want to see. The drop-down panel groups controls by room, so a glance stays useful even when the installation grows.

![PearchHA menu bar panel with rooms and controls]({{ '/assets/help/panel.png' | relative_url }})

Controls are based on the Home Assistant capability of each entity. PearchHA does not guess which action is safe or meaningful.

For local values, open **Settings > Entities > This Mac**. Select CPU, memory,
battery or thermal readings for the panel, or enable their menu-bar visibility.
These read-only sensors also work without Home Assistant. Battery entries appear
only on Macs with an internal battery. Thermal state is a macOS load category,
not a temperature. Local values have no recorded history. Their labels follow
the Mac's preferred language, with German and English available.

## History

<a id="history"></a>

Click an entity’s history preview to see its recent history. Back or Escape returns to the room overview without losing its scroll position. Expand Recorded values for exact timestamps and values, including keyboard and screen-reader access. Use the detail view when you need an hour, day, week or month of context without leaving the app.

![Entity history detail]({{ '/assets/help/history.png' | relative_url }})

## Settings

<a id="settings"></a>

Settings control the Home Assistant connection, timed refreshes, live updates while the panel is open, labels and per-entity presentation. Each choice remains local to your Mac. In Entities, choose a room and use search, type or capability filters to find a value. Select its row to open details without moving the list. Panel selection and menu-bar visibility remain independent. Clear filters before reordering.

In **Appearance > Text size**, choose 100% to 200%. Larger text also applies to
history, entity details and control editors. The panel grows and rows wrap while
keeping the same actions. Menu-bar labels and values share one line at larger
sizes to fit the macOS menu bar.

![PearchHA settings]({{ '/assets/help/settings.png' | relative_url }})

To transfer settings from an existing installation, choose **PearchHA > Import Settings…**
while Settings is open. Select its `config.json`, then confirm **Import and Quit**.
Reopen PearchHA to apply the imported settings. The original file is unchanged.
Tokens and protected custom-action values are not copied, so sign in again if
the new installation cannot access the existing Keychain entries. Direct
installations keep configuration in `~/Library/Application Support/PearchHA/`.
