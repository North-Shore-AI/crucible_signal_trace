defmodule CrucibleSignalTrace.TraceFragment do
  @moduledoc """
  Typed validated slice of a trace event stream.
  """

  alias CrucibleSignalTrace.{SafeTerms, Validate}

  @derive Jason.Encoder
  defstruct fragment_id: nil,
            trace_id: nil,
            ordinal: 0,
            source: nil,
            events: [],
            event_count: 0,
            started_at: nil,
            ended_at: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs = SafeTerms.normalize_keys(attrs)
    events = Map.get(attrs, :events, [])

    with :ok <- require_fields(attrs, [:trace_id]),
         :ok <- require_events(events),
         {:ok, validated_events} <- validate_events(events, Map.fetch!(attrs, :trace_id)) do
      {:ok,
       %__MODULE__{
         fragment_id:
           Map.get(attrs, :fragment_id, "fragment:#{System.unique_integer([:positive])}"),
         trace_id: Map.fetch!(attrs, :trace_id),
         ordinal: Map.get(attrs, :ordinal, 0),
         source: Map.get(attrs, :source),
         events: validated_events,
         event_count: length(validated_events),
         started_at: Map.get(attrs, :started_at),
         ended_at: Map.get(attrs, :ended_at),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, fragment} -> fragment
      {:error, reason} -> raise ArgumentError, "invalid trace fragment: #{inspect(reason)}"
    end
  end

  defp validate_events(events, trace_id) do
    Enum.reduce_while(events, {:ok, []}, fn event, {:ok, acc} ->
      case Validate.validate_event(event) do
        {:ok, %{trace_id: ^trace_id} = event} ->
          {:cont, {:ok, [event | acc]}}

        {:ok, event} ->
          {:halt, {:error, {:trace_id_mismatch, trace_id, Map.get(event, :trace_id)}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp require_fields(attrs, fields) do
    missing = Enum.reject(fields, &(Map.get(attrs, &1) not in [nil, ""]))
    if missing == [], do: :ok, else: {:error, {:missing_required_fields, missing}}
  end

  defp require_events(events) when is_list(events) and events != [], do: :ok
  defp require_events(_events), do: {:error, :empty_fragment_events}
end
