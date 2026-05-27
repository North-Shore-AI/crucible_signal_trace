# Layer Trajectory

Layer trajectories track how hidden-state vectors change across depth.

## What This Covers

Cosine drift requires raw or compressed vectors. Summaries alone are insufficient.

## Worked Example

```elixir
trajectory = CrucibleSignalTrace.LayerTrajectory.new!([
  %{layer_index: 1, vector: [1.0, 0.0]},
  %{layer_index: 2, vector: [0.0, 1.0]}
])

CrucibleSignalTrace.LayerTrajectory.cosine_drifts(trajectory)
```

## Related Guides

- [Forward Trace](forward_trace.md)
- [Testing](testing.md)
