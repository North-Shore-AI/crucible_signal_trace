defmodule Crucible.ForwardTrace do
  @moduledoc """
  Canonical forward trace transaction assembled from bounded signal events.
  """

  @derive Jason.Encoder
  defstruct [
    :trace_id,
    :run_id,
    :provider_kind,
    :model_id,
    :model_family,
    :backend,
    :input_hash,
    :prompt_digest,
    :tap_plan_ref,
    :tap_plan_digest,
    :capability_report_digest,
    :layer_trajectory,
    :final_logits,
    :cache_summary,
    events: [],
    signals: [],
    decoding_steps: [],
    policy_decision_refs: [],
    capability_report: nil,
    started_at: nil,
    ended_at: nil,
    completed_at: nil,
    duration_ms: nil,
    status: nil,
    metadata: %{}
  ]

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs = atom_keys(attrs)

    with :ok <- require_fields(attrs, [:trace_id]) do
      {:ok,
       %__MODULE__{
         trace_id: Map.fetch!(attrs, :trace_id),
         run_id: Map.get(attrs, :run_id),
         provider_kind: Map.get(attrs, :provider_kind),
         model_id: Map.get(attrs, :model_id) || Map.get(attrs, :model_ref),
         model_family: Map.get(attrs, :model_family),
         backend: Map.get(attrs, :backend),
         input_hash: Map.get(attrs, :input_hash),
         prompt_digest: Map.get(attrs, :prompt_digest),
         tap_plan_ref: Map.get(attrs, :tap_plan_ref),
         tap_plan_digest: Map.get(attrs, :tap_plan_digest),
         capability_report_digest: Map.get(attrs, :capability_report_digest),
         layer_trajectory: Map.get(attrs, :layer_trajectory),
         final_logits: Map.get(attrs, :final_logits),
         cache_summary: Map.get(attrs, :cache_summary, %{}),
         events: Map.get(attrs, :events, []),
         signals: Enum.map(Map.get(attrs, :signals, []), &canonical_signal!/1),
         decoding_steps: Map.get(attrs, :decoding_steps, []),
         policy_decision_refs: Map.get(attrs, :policy_decision_refs, []),
         capability_report: Map.get(attrs, :capability_report),
         started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
         ended_at: Map.get(attrs, :ended_at),
         completed_at: Map.get(attrs, :completed_at),
         duration_ms: Map.get(attrs, :duration_ms),
         status: Map.get(attrs, :status),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, trace} -> trace
      {:error, reason} -> raise ArgumentError, "invalid forward trace: #{inspect(reason)}"
    end
  end

  @spec complete(t(), DateTime.t()) :: t()
  def complete(%__MODULE__{} = trace, completed_at \\ DateTime.utc_now()) do
    %{trace | completed_at: completed_at, ended_at: completed_at, status: trace.status || :ok}
  end

  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = trace), do: CrucibleSignalTrace.Digest.term(trace)

  defp canonical_signal!(%Crucible.SignalRecord{} = signal), do: signal

  defp canonical_signal!(signal) when is_map(signal) or is_list(signal),
    do: Crucible.SignalRecord.new!(signal)

  defp require_fields(attrs, fields) do
    missing =
      Enum.reject(fields, &(Map.has_key?(attrs, &1) and Map.get(attrs, &1) not in [nil, ""]))

    if missing == [], do: :ok, else: {:error, {:missing_required_fields, missing}}
  end

  defp atom_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
