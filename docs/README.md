# PearchHA docs

Start here, then go one level deeper only when you need it.

| File | Answers |
| --- | --- |
| [ROADMAP.md](ROADMAP.md) | What still blocks a public release and what comes next. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the app is structured, where state lives, and which runtime rules keep it cheap and stable. |
| [HA_API.md](HA_API.md) | Which Home Assistant APIs and mirrored fixture boundaries PearchHA relies on. |
| [TESTING.md](TESTING.md) | How the project is verified, what the coverage gates are, and where the remaining evidence gaps are. |
| [ADRs.md](ADRs.md) | Binding technical decisions and rejected alternatives. |
| [../Fixtures/README.md](../Fixtures/README.md) | What belongs in the mirrored fixture tree and what must stay private. |

## Precedence

When docs disagree:

1. [ADRs.md](ADRs.md) wins for accepted decisions.
2. [HA_API.md](HA_API.md) wins for Home Assistant wire behavior.
3. [TESTING.md](TESTING.md) wins for verification rules and coverage contracts.
4. [ARCHITECTURE.md](ARCHITECTURE.md) describes the current implementation.
5. [ROADMAP.md](ROADMAP.md) tracks remaining work, not alternate truth.

Keep one question per document. Update its canonical source instead of adding parallel notes.
