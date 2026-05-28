# Provider Neutral Traces

Purpose: describe the V5 JSONL trace stream accepted by the replay stack.

## What this covers

Every V5 event row carries `"schema_version": "crucible.trace.v4"`,
`event_type`, and `trace_id`. Signal rows contain summaries and references only;
inline raw tensor arrays are rejected by `CrucibleSignalTrace.Validate`.

## Quickstart

```elixir
{:ok, trace} =
  CrucibleSignalTrace.Ingest.from_jsonl("tmp/crucible_v5/traces/native/model_forward_live.trace.jsonl")

trace.signals
```

To write an event:

```elixir
CrucibleSignalTrace.JSONL.write_event!(
  "tmp/crucible_v5/traces/native/example.trace.jsonl",
  CrucibleSignalTrace.JSONL.v4_event(:trace_start, trace_id: "tr_1")
)
```

## Related guides

- [JSONL Persistence](jsonl_persistence.md)
- [Forward Trace](forward_trace.md)
