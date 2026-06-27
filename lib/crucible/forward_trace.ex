defmodule Crucible.ForwardTrace do
  @moduledoc """
  Canonical forward trace transaction assembled from bounded signal events.
  """

  alias CrucibleSignalTrace.SafeTerms

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
    attrs = attrs |> atom_keys() |> normalize_trace_attrs()

    with :ok <- require_fields(attrs, [:trace_id]) do
      {:ok,
       %__MODULE__{
         trace_id: Map.fetch!(attrs, :trace_id),
         run_id: Map.get(attrs, :run_id),
         provider_kind: atomize(Map.get(attrs, :provider_kind)),
         model_id: Map.get(attrs, :model_id) || Map.get(attrs, :model_ref),
         model_family: atomize(Map.get(attrs, :model_family)),
         backend: atomize(Map.get(attrs, :backend)),
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
         status: atomize(Map.get(attrs, :status)),
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

  defp canonical_signal!(signal) when is_map(signal) or is_list(signal) do
    signal
    |> Map.new()
    |> normalize_keys()
    |> normalize_signal_attrs()
    |> then(&Crucible.SignalRecord.new!/1)
  end

  defp normalize_trace_attrs(attrs) when is_map(attrs) do
    Map.update(attrs, :signals, [], fn signals ->
      Enum.map(signals, &canonical_signal!/1)
    end)
  end

  defp normalize_signal_attrs(signal) when is_map(signal) do
    signal
    |> Map.update(:signal_type, nil, &atomize/1)
    |> Map.update(:provider_kind, nil, &atomize/1)
    |> Map.update(:model_family, nil, &atomize/1)
    |> Map.update(:backend, nil, &atomize/1)
    |> Map.update(:dtype, nil, &atomize/1)
    |> Map.update(:capture_method, nil, &atomize/1)
    |> Map.update(:capability_status, nil, &atomize/1)
    |> Map.update(:capability_reason, nil, &atomize/1)
    |> Map.update(:tensor_summary, nil, &normalize_tensor_summary/1)
  end

  defp normalize_tensor_summary(nil), do: nil
  defp normalize_tensor_summary(%Crucible.TensorSummary{} = summary), do: summary

  defp normalize_tensor_summary(summary) when is_map(summary) do
    summary = normalize_keys(summary)

    struct(Crucible.TensorSummary, %{
      shape: Map.get(summary, :shape, []),
      rank: Map.get(summary, :rank, 0),
      dtype: atomize(Map.get(summary, :dtype)),
      min: Map.get(summary, :min),
      max: Map.get(summary, :max),
      mean: Map.get(summary, :mean),
      stddev: Map.get(summary, :stddev),
      norm_l2: Map.get(summary, :norm_l2),
      nan_count: Map.get(summary, :nan_count, 0),
      positive_infinity_count: Map.get(summary, :positive_infinity_count, 0),
      negative_infinity_count: Map.get(summary, :negative_infinity_count, 0),
      entropy: Map.get(summary, :entropy),
      top_k: Map.get(summary, :top_k),
      digest: Map.get(summary, :digest)
    })
  end

  defp normalize_tensor_summary(summary), do: summary

  defp atomize(nil), do: nil
  defp atomize(value) when is_atom(value), do: value
  defp atomize(value) when is_binary(value), do: SafeTerms.atomize_existing(value)
  defp atomize(value), do: value

  defp normalize_keys(value) when is_map(value), do: SafeTerms.normalize_keys(value)

  defp require_fields(attrs, fields) do
    missing =
      Enum.reject(fields, &(Map.has_key?(attrs, &1) and Map.get(attrs, &1) not in [nil, ""]))

    if missing == [], do: :ok, else: {:error, {:missing_required_fields, missing}}
  end

  defp atom_keys(attrs), do: SafeTerms.normalize_keys(attrs)
end
