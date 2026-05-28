defmodule CrucibleSignalTrace.Ingest do
  @moduledoc """
  V4/V5 JSONL ingestion and ForwardTrace assembly.
  """

  alias Crucible.ForwardTrace
  alias CrucibleSignalTrace.JSONL

  @spec from_jsonl(String.t(), keyword()) :: {:ok, ForwardTrace.t()} | {:error, term()}
  def from_jsonl(path, opts \\ []) when is_binary(path) do
    {:ok, from_jsonl!(path, opts)}
  rescue
    error -> {:error, error}
  end

  @spec from_jsonl!(String.t(), keyword()) :: ForwardTrace.t()
  def from_jsonl!(path, opts \\ []) when is_binary(path) do
    events =
      path
      |> File.read!()
      |> String.split(["\n", "\r\n"], trim: true)
      |> Enum.map(&JSONL.decode_v4_event!/1)

    assemble(events, Keyword.put(opts, :trace_digest, CrucibleSignalTrace.Digest.file(path)))
  end

  @spec from_directory!(String.t(), keyword()) :: [ForwardTrace.t()]
  def from_directory!(directory, opts \\ []) when is_binary(directory) do
    directory
    |> trace_paths(Keyword.get(opts, :pattern, "**/*.jsonl"))
    |> Enum.map(&from_jsonl!(&1, opts))
  end

  @spec from_directory(String.t(), keyword()) :: {:ok, [ForwardTrace.t()]} | {:error, term()}
  def from_directory(directory, opts \\ []) when is_binary(directory) do
    {:ok, from_directory!(directory, opts)}
  rescue
    error -> {:error, error}
  end

  @spec assemble([map()], keyword()) :: ForwardTrace.t()
  def assemble(events, opts \\ []) when is_list(events) do
    normalized = Enum.map(events, &normalize_keys/1)
    start = Enum.find(normalized, &(Map.get(&1, :event_type) == "trace_start")) || %{}

    finish =
      Enum.find(Enum.reverse(normalized), &(Map.get(&1, :event_type) == "trace_end")) || %{}

    capability =
      Enum.find(normalized, &(Map.get(&1, :event_type) == "provider_capability_report"))

    %ForwardTrace{
      trace_id: Map.get(start, :trace_id) || trace_id(normalized),
      run_id: Map.get(start, :run_id),
      provider_kind: atomize(Map.get(start, :provider_kind)),
      model_id: Map.get(start, :model_id),
      model_family: atomize(Map.get(start, :model_family)),
      backend: atomize(Map.get(start, :backend)),
      prompt_digest: first_value(normalized, :prompt_digest),
      tap_plan_digest: first_value(normalized, :tap_plan_digest),
      capability_report_digest: first_value(normalized, :capability_report_digest),
      events: normalized,
      signals: signals(normalized),
      capability_report: capability_report(capability),
      started_at: parse_time(Map.get(start, :timestamp)),
      ended_at: parse_time(Map.get(finish, :timestamp)),
      duration_ms: Map.get(finish, :duration_ms),
      status: atomize(Map.get(finish, :status) || "ok"),
      metadata: %{trace_digest: Keyword.get(opts, :trace_digest)}
    }
  end

  defp signals(events) do
    events
    |> Enum.filter(&(Map.get(&1, :event_type) == "signal_record"))
    |> Enum.map(&Map.get(&1, :signal))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&signal_record/1)
  end

  defp signal_record(%Crucible.SignalRecord{} = record), do: record

  defp signal_record(signal) when is_map(signal) do
    signal = normalize_keys(signal)

    %Crucible.SignalRecord{
      signal_id: Map.get(signal, :signal_id),
      trace_id: Map.get(signal, :trace_id),
      run_id: Map.get(signal, :run_id),
      signal_type: atomize(Map.get(signal, :signal_type)),
      provider_kind: atomize(Map.get(signal, :provider_kind)),
      model_id: Map.get(signal, :model_id),
      model_family: atomize(Map.get(signal, :model_family)),
      model_revision: Map.get(signal, :model_revision),
      backend: atomize(Map.get(signal, :backend)),
      dtype: atomize(Map.get(signal, :dtype)),
      shape: Map.get(signal, :shape),
      rank: Map.get(signal, :rank),
      device: Map.get(signal, :device),
      layer_index: Map.get(signal, :layer_index),
      token_index: Map.get(signal, :token_index),
      node_name: Map.get(signal, :node_name),
      capture_method: atomize(Map.get(signal, :capture_method)),
      surface_id: Map.get(signal, :surface_id),
      tap_id: Map.get(signal, :tap_id),
      capability_status: atomize(Map.get(signal, :capability_status)),
      capability_reason: atomize(Map.get(signal, :capability_reason)),
      tensor_summary: tensor_summary(Map.get(signal, :tensor_summary)),
      tensor_ref: tensor_ref(Map.get(signal, :tensor_ref)),
      metadata: Map.get(signal, :metadata, %{})
    }
  end

  defp tensor_summary(nil), do: nil
  defp tensor_summary(%Crucible.TensorSummary{} = summary), do: summary

  defp tensor_summary(summary) when is_map(summary) do
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
      entropy: Map.get(summary, :entropy),
      top_k: Map.get(summary, :top_k),
      digest: Map.get(summary, :digest)
    })
  end

  defp tensor_ref(nil), do: nil
  defp tensor_ref(%Crucible.TensorRef{} = ref), do: ref
  defp tensor_ref(ref) when is_map(ref), do: struct(Crucible.TensorRef, normalize_keys(ref))
  defp tensor_ref(_ref), do: nil

  defp capability_report(nil), do: nil
  defp capability_report(%{capability_report: report}), do: report
  defp capability_report(%{"capability_report" => report}), do: report

  defp trace_paths(directory, pattern) do
    directory
    |> Path.join(pattern)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.sort()
  end

  defp first_value(events, key) do
    events
    |> Enum.find_value(&Map.get(&1, key))
  end

  defp trace_id([event | _events]), do: Map.get(event, :trace_id)
  defp trace_id([]), do: nil

  defp parse_time(nil), do: nil

  defp parse_time(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp atomize(nil), do: nil
  defp atomize(value) when is_atom(value), do: value
  defp atomize(value) when is_binary(value), do: String.to_atom(value)
  defp atomize(value), do: value

  defp normalize_keys(value) when is_map(value) do
    Map.new(value, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), normalize_nested(value)}
      {key, value} -> {key, normalize_nested(value)}
    end)
  end

  defp normalize_nested(value) when is_map(value), do: normalize_keys(value)
  defp normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  defp normalize_nested(value), do: value
end
