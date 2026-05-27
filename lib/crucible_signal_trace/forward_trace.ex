defmodule CrucibleSignalTrace.ForwardTrace do
  @moduledoc """
  Bounded record of one model forward pass.
  """

  alias CrucibleSignal.SignalRef
  alias CrucibleSignalTrace.{Digest, LayerTrajectory, SignalRecord}

  @derive Jason.Encoder
  defstruct trace_id: nil,
            model_ref: nil,
            input_hash: nil,
            tap_plan_ref: nil,
            signal_records: [],
            layer_trajectory: nil,
            final_logits: nil,
            cache_summary: %{},
            decoding_steps: [],
            policy_decision_refs: [],
            started_at: nil,
            completed_at: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with :ok <- require_fields(attrs, [:trace_id, :model_ref]) do
      signal_records = Enum.map(Map.get(attrs, :signal_records, []), &normalize_record/1)

      {:ok,
       %__MODULE__{
         trace_id: Map.fetch!(attrs, :trace_id),
         model_ref: Map.fetch!(attrs, :model_ref),
         input_hash: Map.get(attrs, :input_hash),
         tap_plan_ref: Map.get(attrs, :tap_plan_ref),
         signal_records: signal_records,
         layer_trajectory: normalize_trajectory(Map.get(attrs, :layer_trajectory)),
         final_logits: normalize_signal_ref(Map.get(attrs, :final_logits)),
         cache_summary: Map.get(attrs, :cache_summary, %{}),
         decoding_steps: Map.get(attrs, :decoding_steps, []),
         policy_decision_refs: Map.get(attrs, :policy_decision_refs, []),
         started_at: Map.get(attrs, :started_at, DateTime.utc_now()),
         completed_at: Map.get(attrs, :completed_at),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, trace} -> trace
      {:error, reason} -> raise ArgumentError, "invalid forward trace: #{inspect(reason)}"
    end
  end

  def complete(%__MODULE__{} = trace, completed_at \\ DateTime.utc_now()) do
    %{trace | completed_at: completed_at}
  end

  def digest(%__MODULE__{} = trace), do: Digest.term(trace)

  defp normalize_record(%SignalRecord{} = record), do: record
  defp normalize_record(attrs), do: SignalRecord.new!(attrs)

  defp normalize_trajectory(nil), do: nil
  defp normalize_trajectory(%LayerTrajectory{} = trajectory), do: trajectory
  defp normalize_trajectory(points) when is_list(points), do: LayerTrajectory.new!(points)

  defp normalize_signal_ref(nil), do: nil
  defp normalize_signal_ref(%SignalRef{} = ref), do: ref
  defp normalize_signal_ref(attrs), do: SignalRef.new!(attrs)

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp require_fields(attrs, fields) do
    missing =
      Enum.reject(fields, &(Map.has_key?(attrs, &1) and Map.get(attrs, &1) not in [nil, ""]))

    if missing == [], do: :ok, else: {:error, {:missing_required_fields, missing}}
  end
end
