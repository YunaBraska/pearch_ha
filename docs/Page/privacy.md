---
layout: default
help: true
title: Privacy policy
description: How PearchHA handles Home Assistant data and local settings.
---

# Privacy policy

PearchHA connects your Mac to the Home Assistant addresses you choose. It reads
entity names, states, capabilities, room assignments and history to display and
control your installation. Actions you request are sent to your Home Assistant.
The app does not send these credentials or entity data to its developer.

## Storage and retention

Connection and display preferences are stored in Application Support on your Mac.
Access tokens, refresh tokens and protected custom-action values are stored in
macOS Keychain. History caches are held in memory while the app runs. PearchHA
has no developer-operated account or cloud database for your Home Assistant data.
Home Assistant itself retains data according to the settings of your server.

Signing out removes the saved sign-in session. Remove custom actions to remove
their protected values. You can also revoke tokens from your Home Assistant
profile. Removing the app does not automatically erase macOS Keychain entries or
preferences. You can remove PearchHA entries using Keychain Access and the
PearchHA preferences folder using Finder. Back up settings you want to keep first.

## Network connections

PearchHA includes no advertising or analytics SDK. Direct-download builds contact
GitHub and the update feed for application updates. These servers receive ordinary
connection information such as IP address and app version. App Store builds use
Apple's update system and do not run the direct-download updater.
Links you choose open in your browser and are governed by the destination's
privacy policy. Network access to your Home Assistant is necessary for connected
features. Local-network permission can be managed in macOS System Settings.

## Support

Diagnostics can include connection outcomes, entity identifiers and error messages.
Review information before sharing it. Never post access tokens or private Home
Assistant addresses in a public issue. For privacy questions, contact the project
through its [support page](https://github.com/YunaBraska/pearch_ha/issues).
