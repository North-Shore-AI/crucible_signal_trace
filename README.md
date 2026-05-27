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

## Usage

```elixir
alias CrucibleSignal.SignalRef
alias CrucibleSignalTrace.{ForwardTrace, JSONL}

logits_ref =
  SignalRef.new!(
    trace_id: "trace-1",
    signal_id: "final-logits",
    signal_type: :final_logits
  )

trace =
  ForwardTrace.new!(
    trace_id: "trace-1",
    model_ref: "model:local",
    final_logits: logits_ref,
    cache_summary: %{blocks: 28}
  )

line = JSONL.encode_line!(trace)
```

## Guides

- [Quickstart](guides/quickstart.md)
- [Concepts](guides/concepts.md)
- [Forward Trace](guides/forward_trace.md)
- [Provider Neutral Traces](guides/provider_neutral_traces.md)
- [Layer Trajectory](guides/layer_trajectory.md)
- [JSONL Persistence](guides/jsonl_persistence.md)
- [AITrace Export](guides/ai_trace_export.md)
- [Redaction](guides/redaction.md)
- [Working Examples](guides/working_examples.md)
- [Testing](guides/testing.md)

## Examples

- `examples/trace_jsonl_mock.exs`
- `examples/aitrace_export_live.exs`

## Testing

- Default suite: `mix test`
- Full local gate: `mix ci`

Documentation can be generated with `mix docs` and published to HexDocs.

## V4 Status

Status: `schema-compatible`.

V4 trace streams use `"schema_version": "crucible.trace.v4"`.
`CrucibleSignalTrace.JSONL.write_event!/2`,
`CrucibleSignalTrace.JSONL.stream!/1`, `CrucibleSignalTrace.Validate`, and
`CrucibleSignalTrace.Ingest.from_jsonl/2` validate and assemble provider-neutral
JSONL traces without inline raw tensor arrays.
