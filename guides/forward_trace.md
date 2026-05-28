# Forward Trace

Forward traces contain bounded records for one model pass.

## What This Covers

Traces reference signals and summaries; they should not embed raw tensors.

## Worked Example

```elixir
Crucible.ForwardTrace.new!(trace_id: "trace-1", model_id: "model")
```

## Related Guides

- [JSONL Persistence](jsonl_persistence.md)
- [Redaction](redaction.md)
