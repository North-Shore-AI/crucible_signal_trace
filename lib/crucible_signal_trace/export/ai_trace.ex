defmodule CrucibleSignalTrace.Export.AITrace do
  @moduledoc """
  Lightweight AITrace-compatible event payload conversion.

  The package does not depend on AITrace. Consumers that use AITrace can pass
  this event map to their own AITrace facade.
  """

  @callback to_evidence(Crucible.ForwardTrace.t()) :: {:ok, map()} | {:error, term()}

  def event(%Crucible.ForwardTrace{} = trace) do
    %{
      name: "crucible.forward_trace",
      trace_id: trace.trace_id,
      attributes: %{
        model_ref: trace.model_id,
        input_hash: trace.input_hash,
        tap_plan_ref: trace.tap_plan_ref,
        signal_count: length(trace.signals),
        has_layer_trajectory: trace.layer_trajectory != nil,
        digest: Crucible.ForwardTrace.digest(trace)
      }
    }
  end

  def to_evidence(%Crucible.ForwardTrace{} = trace),
    do: CrucibleSignalTrace.Export.AITrace.V1.to_evidence(trace)
end
