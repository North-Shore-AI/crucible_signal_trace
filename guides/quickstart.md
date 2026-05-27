# Quickstart

Build forward traces and stream trace events as JSONL.

## What This Covers

This guide creates a trace and writes one event envelope.

## Worked Example

```elixir
trace = CrucibleSignalTrace.forward_trace!(trace_id: "trace-1", model_ref: "model")
CrucibleSignalTrace.JSONL.encode_line!(CrucibleSignalTrace.JSONL.trace_start(trace.trace_id))
```

## Related Guides

- [Forward Trace](forward_trace.md)
- [JSONL Persistence](jsonl_persistence.md)
