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

## History

<a id="history"></a>

Open an entity to see its recent history. Use the detail view when you need an hour, day, week or month of context without leaving the app.

![Entity history detail]({{ '/assets/help/history.png' | relative_url }})

## Settings

<a id="settings"></a>

Settings control the Home Assistant connection, timed refreshes, live updates while the panel is open, labels and per-entity presentation. Each choice remains local to your Mac.

![PearchHA settings]({{ '/assets/help/settings.png' | relative_url }})
