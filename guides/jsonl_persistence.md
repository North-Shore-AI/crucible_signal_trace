# JSONL Persistence

JSONL persistence stores trace events incrementally.

## What This Covers

Use event envelopes for trace starts, signal records, token steps, and trace ends.

## Worked Example

```elixir
events = [
  CrucibleSignalTrace.JSONL.trace_start("trace-1"),
  CrucibleSignalTrace.JSONL.trace_end("trace-1")
]

CrucibleSignalTrace.JSONL.stream_encode("/tmp/trace.jsonl", events)
```

## Related Guides

- [Quickstart](quickstart.md)
- [Working Examples](working_examples.md)
