# Forward Trace

Forward traces contain bounded records for one model pass.

## What This Covers

Traces reference signals and summaries; they should not embed raw tensors.
Canonical activation metadata belongs on each `Crucible.SignalRecord.metadata`
map when the signal is meant to be replayed into mechanistic-interpretability
tools:

```elixir
%{
  activation_name: "blocks.0.attn.hook_q",
  component: :attn,
  layer_index: 0,
  axes: [:batch, :pos, :head, :d_head]
}
```

`CrucibleSignalTrace.Validate.validate_forward_trace/2` rejects malformed
activation metadata. Replay derives `CrucibleTap.SurfaceNode` entries from
recorded signals and preserves `activation_name`, `component`, and `axes`, so tap
plans can be negotiated against a trace without a live provider.

Summary-only traces stay summary-only: a required raw activation tap fails unless
the signal includes a raw tensor artifact reference through `tensor_ref` or
metadata `raw_ref`.

## Worked Example

```elixir
Crucible.ForwardTrace.new!(trace_id: "trace-1", model_id: "model")
```

## Related Guides

- [JSONL Persistence](jsonl_persistence.md)
- [Redaction](redaction.md)
