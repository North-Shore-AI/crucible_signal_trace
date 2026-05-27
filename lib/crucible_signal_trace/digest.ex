defmodule CrucibleSignalTrace.Digest do
  @moduledoc """
  Stable digest helpers for trace payloads.
  """

  def term(value), do: value |> :erlang.term_to_binary() |> sha256()
  def text(value) when is_binary(value), do: sha256(value)

  defp sha256(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end
end
