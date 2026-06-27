defmodule CrucibleSignalTrace.TraceEvent do
  @moduledoc """
  Serializable event emitted from a forward trace.
  """

  alias CrucibleSignalTrace.SafeTerms

  @derive Jason.Encoder
  defstruct event_id: nil,
            trace_id: nil,
            event_type: nil,
            occurred_at: nil,
            payload: %{},
            metadata: %{}

  @type t :: %__MODULE__{}

  def new!(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    %__MODULE__{
      event_id: Map.get(attrs, :event_id, "event:#{System.unique_integer([:positive])}"),
      trace_id: Map.fetch!(attrs, :trace_id),
      event_type: Map.fetch!(attrs, :event_type),
      occurred_at: Map.get(attrs, :occurred_at, DateTime.utc_now()),
      payload: Map.get(attrs, :payload, %{}),
      metadata: Map.get(attrs, :metadata, %{})
    }
  end

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs), do: SafeTerms.normalize_keys(attrs)
end
