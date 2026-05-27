# Concepts

CrucibleSignalTrace records evidence from model passes without owning execution.

## What This Covers

The package stores signal records, trajectories, decode events, redaction metadata, and export evidence.

## Worked Example

```elixir
CrucibleSignalTrace.JSONL.trace_start("trace-1")
```

## Related Guides

- [Layer Trajectory](layer_trajectory.md)
- [AITrace Export](ai_trace_export.md)
