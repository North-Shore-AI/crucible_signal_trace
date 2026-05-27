defmodule CrucibleSignalTrace.Digest do
  @moduledoc """
  Stable digest helpers for trace payloads.
  """

  def term(value), do: value |> :erlang.term_to_binary() |> sha256()
  def text(value) when is_binary(value), do: sha256(value)
  def file(path) when is_binary(path), do: path |> File.read!() |> sha256_prefixed()

  def prefixed_term(value), do: "sha256:" <> term(value)
  def prefixed_text(value) when is_binary(value), do: "sha256:" <> text(value)

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end

  defp sha256_prefixed(data), do: "sha256:" <> sha256(data)
end
