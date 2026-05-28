# AITrace Export

AITrace export produces a versioned evidence map without taking a runtime dependency.

## What This Covers

`Export.AITrace.V1` has a stable schema checked by tests.

## Worked Example

```elixir
trace = Crucible.ForwardTrace.new!(trace_id: "trace-1", model_id: "model")
CrucibleSignalTrace.Export.AITrace.to_evidence(trace)
```

## Related Guides

- [Forward Trace](forward_trace.md)
- [Redaction](redaction.md)
