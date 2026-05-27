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
end
