<p align="center">
  <img src="assets/crucible_signal_trace.svg" width="200" height="200" alt="crucible_signal_trace logo" />
</p>

<p align="center">
  <a href="https://github.com/North-Shore-AI/crucible_signal_trace">
    <img alt="GitHub: crucible_signal_trace" src="https://img.shields.io/badge/GitHub-crucible_signal_trace-0b0f14?logo=github" />
  </a>
  <a href="https://github.com/North-Shore-AI/crucible_signal_trace/blob/main/LICENSE">
    <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-0b0f14.svg" />
  </a>
</p>

# CrucibleSignalTrace

Bounded forward-pass trace schema and persistence helpers for Crucible signal
captures, layer trajectories, and decode telemetry.

## Stack Position

`crucible_signal_trace` sits above `crucible_signal` and `crucible_tap`. It
records what happened in a model pass without owning model execution or policy
authority.

## Installation

```elixir
def deps do
  [
    {:crucible_signal_trace, "~> 0.1.0"}
  ]
end
```

## Boundary

This package owns trace records, signal records, layer trajectories, JSONL
persistence, bounded redaction, and export helpers. It does not run models or
decide routes.

Documentation can be generated with `mix docs` and published to HexDocs.
