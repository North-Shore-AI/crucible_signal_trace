# JSONL Persistence

JSONL persistence stores trace events incrementally.

## What This Covers

Use event envelopes for trace starts, signal records, token steps, and trace ends.

## Worked Example

```elixir
events = [
  CrucibleSignalTrace.JSONL.trace_start("trace-1"),
  CrucibleSignalTrace.JSONL.token_step("trace-1", 0, "sig-logits-0"),
  CrucibleSignalTrace.JSONL.trace_end("trace-1")
]

CrucibleSignalTrace.JSONL.stream_encode("/tmp/trace.jsonl", events)
```

`CrucibleSignalTrace.Validate.validate_forward_trace/2` supports `:shape`,
`:events`, and `:replay` validation levels. Use `:events` when validating a
canonical JSONL stream attached to a trace, and `:replay` when the trace must
carry replay-safe capability evidence.

## Related Guides

- [Quickstart](quickstart.md)
- [Working Examples](working_examples.md)
