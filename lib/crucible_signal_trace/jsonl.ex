defmodule CrucibleSignalTrace.JSONL do
  @moduledoc """
  JSON Lines helpers for bounded forward traces and events.
  """

  @schema_version "crucible.trace.v4"

  def encode_line!(value), do: Jason.encode!(value) <> "\n"

  def encode_canonical_line!(value), do: Crucible.CanonicalJSON.encode!(value) <> "\n"

  def decode_line(line) when is_binary(line) do
    line
    |> String.trim_trailing()
    |> Jason.decode()
  end

  @spec decode_v4_event!(String.t()) :: map()
  def decode_v4_event!(line) when is_binary(line) do
    event =
      line
      |> String.trim_trailing()
      |> Jason.decode!()

    unless is_map(event) do
      raise ArgumentError, "expected v4 trace event map, got: #{inspect(event)}"
    end

    CrucibleSignalTrace.Validate.validate_event!(event)
    event
  end

  def append(path, value) when is_binary(path) do
    File.write(path, encode_line!(value), [:append])
  end

  def write_event!(path, value) when is_binary(path) do
    value = normalize_v4_event(value)
    CrucibleSignalTrace.Validate.validate_event!(value)
    File.mkdir_p!(Path.dirname(path))
    :ok = File.write(path, encode_canonical_line!(value), [:append])
    value
  end

  @spec stream!(String.t()) :: Enumerable.t()
  def stream!(path) when is_binary(path) do
    path
    |> File.stream!([], :line)
    |> Stream.map(&decode_v4_event!/1)
  end

  def stream_encode(path, events) when is_binary(path) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case append(path, event) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def stream_decode(path) when is_binary(path) do
    path
    |> File.stream!([], :line)
    |> Stream.map(&decode_line/1)
  end

  def trace_start(trace_id),
    do: %{event_type: :trace_start, trace_id: trace_id, schema_version: 1}

  def v4_event(event_type, attrs) when is_list(attrs) or is_map(attrs) do
    attrs
    |> normalize_map()
    |> Map.put(:event_type, event_type)
    |> Map.put_new(:trace_id, "trace:unspecified")
    |> Map.put_new(:schema_version, @schema_version)
    |> Map.put_new(
      :timestamp,
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    )
  end

  def signal_record(trace_id, token_index, layer, record) do
    %{
      event_type: :signal_record,
      trace_id: trace_id,
      token_index: token_index,
      layer: layer,
      record: record
    }
  end

  def token_step(trace_id, token_index, logits_ref, steering_summary \\ %{}) do
    %{
      event_type: :token_step,
      trace_id: trace_id,
      token_index: token_index,
      logits_ref: logits_ref,
      steering: steering_summary
    }
  end

  def matrix_row(trace_id, matrix, row) when matrix in [:model, :backend, :signal, :generation] do
    v4_event(:"#{matrix}_matrix_row", trace_id: trace_id, row: row)
  end

  def capability_blocker(trace_id, capability, reason, attrs \\ []) do
    v4_event(
      :capability_blocker,
      attrs
      |> normalize_map()
      |> Map.merge(%{trace_id: trace_id, capability: capability, reason: reason})
    )
  end

  def trace_end(trace_id, summary \\ %{}),
    do: %{event_type: :trace_end, trace_id: trace_id, summary: summary}

  defp normalize_v4_event(value) when is_struct(value),
    do: Map.from_struct(value) |> normalize_v4_event()

  defp normalize_v4_event(value) when is_map(value) do
    value
    |> normalize_map()
    |> Map.update(:event_type, nil, &string_or_atom/1)
    |> Map.put_new(:schema_version, @schema_version)
    |> Map.put_new_lazy(:timestamp, fn ->
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    end)
  end

  defp normalize_map(value) when is_list(value), do: value |> Map.new() |> normalize_map()

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), normalize_nested(value)}
      {key, value} -> {key, normalize_nested(value)}
    end)
  end

  defp normalize_nested(value) when is_struct(value),
    do: Map.from_struct(value) |> normalize_map()

  defp normalize_nested(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  defp normalize_nested(value), do: value

  defp string_or_atom(value) when is_binary(value), do: value
  defp string_or_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp string_or_atom(value), do: value
end
