defmodule CrucibleSignalTrace.Export.AITrace do
  @moduledoc """
  Lightweight AITrace-compatible event payload conversion.

  The package does not depend on AITrace. Consumers that use AITrace can pass
  this event map to their own AITrace facade.
  """

  alias CrucibleSignalTrace.ForwardTrace

  def event(%ForwardTrace{} = trace) do
    %{
      name: "crucible.forward_trace",
      trace_id: trace.trace_id,
      attributes: %{
        model_ref: trace.model_ref,
        input_hash: trace.input_hash,
        tap_plan_ref: trace.tap_plan_ref,
        signal_count: length(trace.signal_records),
        has_layer_trajectory: trace.layer_trajectory != nil,
        digest: ForwardTrace.digest(trace)
      }
    }
  end
end
