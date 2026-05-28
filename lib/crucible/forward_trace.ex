defmodule Crucible.ForwardTrace do
  @moduledoc """
  V4/V5 canonical forward trace transaction assembled from JSONL events.
  """

  @derive Jason.Encoder
  defstruct [
    :trace_id,
    :run_id,
    :provider_kind,
    :model_id,
    :model_family,
    :backend,
    :prompt_digest,
    :tap_plan_digest,
    :capability_report_digest,
    events: [],
    signals: [],
    capability_report: nil,
    started_at: nil,
    ended_at: nil,
    duration_ms: nil,
    status: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}
end
