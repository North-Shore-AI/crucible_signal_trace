defmodule CrucibleSignalTrace.Redactor do
  @moduledoc """
  Bounded redaction helpers for trace metadata.
  """

  alias CrucibleSignalTrace.Digest

  @default_limit 512

  def bounded(value, opts \\ [])

  def bounded(value, opts) when is_binary(value) do
    limit = Keyword.get(opts, :limit, @default_limit)

    if byte_size(value) <= limit do
      value
    else
      %{
        redacted: true,
        byte_size: byte_size(value),
        sha256: Digest.text(value),
        preview: binary_part(value, 0, limit)
      }
    end
  end

  def bounded(value, opts) when is_map(value) do
    Map.new(value, fn {key, val} -> {key, bounded(val, opts)} end)
  end

  def bounded(value, opts) when is_list(value), do: Enum.map(value, &bounded(&1, opts))
  def bounded(value, _opts), do: value
end
