defmodule CrucibleSignalTrace.JSONL do
  @moduledoc """
  JSON Lines helpers for bounded forward traces and events.
  """

  def encode_line!(value), do: Jason.encode!(value) <> "\n"

  def decode_line(line) when is_binary(line) do
    line
    |> String.trim_trailing()
    |> Jason.decode()
  end

  def append(path, value) when is_binary(path) do
    File.write(path, encode_line!(value), [:append])
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

  def trace_end(trace_id, summary \\ %{}),
    do: %{event_type: :trace_end, trace_id: trace_id, summary: summary}
end
