defmodule CrucibleSignalTrace.DatasetDigest do
  @moduledoc """
  Deterministic JSONL dataset digest helpers.

  The reader decodes JSON objects with string keys and never converts input
  keys to atoms. Digests preserve row order and canonicalize map key order
  within each row.
  """

  @schema_version "crucible.signal_trace.dataset_digest.v1"

  @type report :: %{
          schema_version: String.t(),
          row_count: non_neg_integer(),
          row_order: String.t(),
          dataset_digest: String.t()
        }

  @spec read_jsonl(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def read_jsonl(path, opts \\ [])

  def read_jsonl(path, opts) when is_binary(path) and is_list(opts) do
    ignore_blank? = Keyword.get(opts, :ignore_blank?, false)

    if File.regular?(path) do
      path
      |> File.stream!(:line, [])
      |> Stream.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {line, line_number}, {:ok, rows} ->
        read_line(path, line_number, line, ignore_blank?, rows)
      end)
      |> case do
        {:ok, rows} -> {:ok, Enum.reverse(rows)}
        error -> error
      end
    else
      {:error, {:jsonl_not_found, path}}
    end
  end

  def read_jsonl(path, _opts), do: {:error, {:invalid_jsonl_path, path}}

  @spec digest_jsonl(String.t(), keyword()) :: {:ok, report()} | {:error, term()}
  def digest_jsonl(path, opts \\ []) when is_binary(path) and is_list(opts) do
    with {:ok, rows} <- read_jsonl(path, opts) do
      digest_rows(rows, opts)
    end
  end

  @spec digest_rows([map()], keyword()) :: {:ok, report()} | {:error, term()}
  def digest_rows(rows, opts \\ [])

  def digest_rows(rows, _opts) when is_list(rows) do
    if Enum.all?(rows, &is_map/1) do
      bytes = Enum.map_join(rows, "", &(canonical_json(&1) <> "\n"))

      {:ok,
       %{
         schema_version: @schema_version,
         row_count: length(rows),
         row_order: "preserved",
         dataset_digest: digest(bytes)
       }}
    else
      {:error, :invalid_dataset_rows}
    end
  end

  def digest_rows(_rows, _opts), do: {:error, :invalid_dataset_rows}

  defp read_line(path, line_number, line, ignore_blank?, rows) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" and ignore_blank? ->
        {:cont, {:ok, rows}}

      trimmed == "" ->
        {:halt, {:error, {:blank_line, path, line_number}}}

      true ->
        decode_line(path, line_number, trimmed, rows)
    end
  end

  defp decode_line(path, line_number, line, rows) do
    case Jason.decode(line) do
      {:ok, row} when is_map(row) ->
        {:cont, {:ok, [row | rows]}}

      {:ok, _other} ->
        {:halt, {:error, {:invalid_json, path, line_number, "expected JSON object"}}}

      {:error, error} ->
        {:halt, {:error, {:invalid_json, path, line_number, Exception.message(error)}}}
    end
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.map(fn {key, nested} -> {to_string(key), nested} end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join(",", fn {key, nested} ->
        Jason.encode!(key) <> ":" <> canonical_json(nested)
      end)

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_boolean(value), do: Jason.encode!(value)

  defp canonical_json(value) when is_atom(value) and not is_nil(value),
    do: Jason.encode!(Atom.to_string(value))

  defp canonical_json(value), do: Jason.encode!(value)

  defp digest(bytes) do
    "sha256:" <>
      (bytes
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end
end
