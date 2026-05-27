defmodule CrucibleSignalTrace.Export.AITrace.V1 do
  @moduledoc """
  Versioned AITrace evidence map exporter.
  """

  @behaviour CrucibleSignalTrace.Export.AITrace

  alias CrucibleSignalTrace.ForwardTrace

  @impl true
  def to_evidence(%ForwardTrace{} = trace) do
    {:ok,
     %{
       schema: "crucible.aitrace.evidence",
       version: 1,
       trace_id: trace.trace_id,
       model: %{ref: trace.model_ref},
       input_digest: trace.input_hash,
       signals: Enum.map(trace.signal_records, &signal_record/1),
       trajectories: trajectory(trace.layer_trajectory),
       decisions: Enum.map(trace.policy_decision_refs, &%{ref: &1}),
       redaction: %{raw_tensors: false},
       digest: ForwardTrace.digest(trace)
     }}
  end

  defp signal_record(record) do
    %{
      signal_id: record.signal_ref.signal_id,
      signal_type: record.signal_ref.signal_type,
      capture_mode: record.capture_mode,
      summary: record.summary,
      value_ref: record.value_ref
    }
  end

  defp trajectory(nil), do: []
  defp trajectory(trajectory), do: [%{points: trajectory.points, metadata: trajectory.metadata}]
end
