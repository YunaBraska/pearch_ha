# FakeHA

FakeHA will replay anonymized Home Assistant fixtures captured by `hamirror`.

Roadmap owner: `M2 - Mirror and FakeHA foundation`.

The M2 foundation serves `/api/` and `/api/states`, journals requests with secret redaction, loads mirrored fixture files, and exposes a WebSocket auth handshake skeleton.
