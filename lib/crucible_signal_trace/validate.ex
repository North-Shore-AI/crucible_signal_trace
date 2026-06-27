defmodule CrucibleSignalTrace.Validate do
  @moduledoc """
  Strict V4/V5 trace event validation.
  """

  @schema_version "crucible.trace.v4"
  alias CrucibleSignal.ActivationMetadata
  alias CrucibleSignalTrace.{SafeTerms, TokenStep}

  @event_types MapSet.new(~w(
    trace_start
    provider_capability_report
    model_load_start
    model_load_end
    tokenizer_load_end
    tap_compile_start
    tap_compile_end
    backend_event
    forward_start
    signal_record
    generation_start
    token_step
    generation_step
    generation_end
    model_matrix_row
    backend_matrix_row
    signal_matrix_row
    generation_matrix_row
    capability_blocker
    policy_decision
    route_decision
    forward_end
    trace_end
    error
  ))

  def schema_version, do: @schema_version
  def event_types, do: MapSet.to_list(@event_types)

  @spec validate_event!(map()) :: map()
  def validate_event!(event) when is_map(event) do
    event =
      event
      |> normalize_keys()
      |> Map.update(:event_type, nil, &SafeTerms.event_type/1)

    with :ok <- require_base(event),
         :ok <- validate_schema(event),
         :ok <- validate_type(event),
         :ok <- validate_payload(event),
         :ok <- validate_no_raw_arrays(event) do
      event
    else
      {:error, reason} -> raise ArgumentError, "invalid Crucible trace event: #{inspect(reason)}"
    end
  end

  def validate_event!(event),
    do: raise(ArgumentError, "expected event map, got: #{inspect(event)}")

  def validate_event(event) when is_map(event) do
    {:ok, validate_event!(event)}
  rescue
    error in ArgumentError -> {:error, error.message}
  end

  @doc """
  Validates a completed forward trace.

  Levels:

    * `:shape` — required trace fields and bounded signal records
    * `:events` — shape plus canonical event stream validation
    * `:replay` — replay-safe shape, event, and capability evidence
  """
  @spec validate_forward_trace(Crucible.ForwardTrace.t(), atom()) :: :ok | {:error, term()}
  def validate_forward_trace(%Crucible.ForwardTrace{} = trace, :shape) do
    with :ok <- require_trace_fields(trace),
         :ok <- validate_signals(trace) do
      :ok
    end
  end

  def validate_forward_trace(%Crucible.ForwardTrace{} = trace, :events) do
    with :ok <- validate_forward_trace(trace, :shape),
         :ok <- validate_trace_events(trace, require_events?: true) do
      :ok
    end
  end

  def validate_forward_trace(%Crucible.ForwardTrace{} = trace, :replay) do
    with :ok <- validate_forward_trace(trace, :shape),
         :ok <- require_capability_report(trace),
         :ok <- validate_trace_events(trace, require_events?: false) do
      :ok
    end
  end

  def validate_forward_trace(trace, level),
    do: {:error, {:unsupported_validation_level, level, trace}}

  defp require_trace_fields(%Crucible.ForwardTrace{} = trace) do
    missing =
      [:trace_id, :provider_kind, :model_id]
      |> Enum.reject(fn field ->
        value = Map.fetch!(trace, field)
        value not in [nil, ""]
      end)

    if missing == [], do: :ok, else: {:error, {:missing_trace_fields, missing}}
  end

  defp validate_signals(%Crucible.ForwardTrace{signals: signals, trace_id: trace_id}) do
    cond do
      signals == [] ->
        {:error, :empty_signals}

      Enum.all?(signals, &match?(%Crucible.SignalRecord{}, &1)) ->
        with :ok <- validate_signal_trace_ids(signals, trace_id),
             :ok <- validate_signal_activation_metadata(signals) do
          :ok
        end

      true ->
        {:error, :invalid_signal_records}
    end
  end

  defp validate_signal_trace_ids(signals, trace_id) do
    mismatched =
      Enum.reject(signals, fn %Crucible.SignalRecord{trace_id: signal_trace_id} ->
        signal_trace_id == trace_id
      end)

    if mismatched == [], do: :ok, else: {:error, {:signal_trace_id_mismatch, trace_id}}
  end

  defp validate_signal_activation_metadata(signals) do
    Enum.reduce_while(signals, :ok, fn %Crucible.SignalRecord{} = signal, :ok ->
      case ActivationMetadata.normalize(signal.metadata) do
        {:ok, _metadata} ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:invalid_signal_activation_metadata, signal.signal_id, reason}}}
      end
    end)
  end

  defp require_base(event) do
    missing =
      [:event_type, :trace_id, :schema_version]
      |> Enum.reject(&(Map.get(event, &1) not in [nil, ""]))

    if missing == [], do: :ok, else: {:error, {:missing_base_keys, missing}}
  end

  defp validate_schema(%{schema_version: @schema_version}), do: :ok
  defp validate_schema(%{schema_version: other}), do: {:error, {:schema_version_mismatch, other}}

  defp validate_type(%{event_type: event_type}) when is_atom(event_type) do
    validate_type(%{event_type: Atom.to_string(event_type)})
  end

  defp validate_type(%{event_type: event_type}) when is_binary(event_type) do
    if MapSet.member?(@event_types, event_type),
      do: :ok,
      else: {:error, {:unknown_event_type, event_type}}
  end

  defp validate_type(event), do: {:error, {:invalid_event_type, Map.get(event, :event_type)}}

  defp validate_payload(%{event_type: "token_step"} = event) do
    case TokenStep.new(event) do
      {:ok, _step} -> :ok
      {:error, reason} -> {:error, {:invalid_token_step, reason}}
    end
  end

  defp validate_payload(_event), do: :ok

  defp validate_trace_events(%Crucible.ForwardTrace{events: events, trace_id: trace_id}, opts) do
    cond do
      events == [] and Keyword.get(opts, :require_events?, false) ->
        {:error, :empty_events}

      events == [] ->
        :ok

      true ->
        validate_event_trace_ids(events, trace_id)
    end
  end

  defp validate_event_trace_ids(events, trace_id) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case validate_event(event) do
        {:ok, %{trace_id: ^trace_id}} ->
          {:cont, :ok}

        {:ok, %{trace_id: other}} ->
          {:halt, {:error, {:event_trace_id_mismatch, trace_id, other}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp require_capability_report(%Crucible.ForwardTrace{capability_report: report})
       when report not in [nil, %{}],
       do: :ok

  defp require_capability_report(%Crucible.ForwardTrace{}),
    do: {:error, :missing_capability_report}

  defp validate_no_raw_arrays(%{event_type: event_type, signal: signal} = event)
       when event_type in ["signal_record", :signal_record] and is_map(signal) do
    cond do
      Map.has_key?(signal, :raw_values) or Map.has_key?(signal, "raw_values") ->
        tiny_fixture?(event)

      tensor_like_array?(Map.get(signal, :tensor) || Map.get(signal, "tensor")) ->
        tiny_fixture?(event)

      true ->
        :ok
    end
  end

  defp validate_no_raw_arrays(_event), do: :ok

  defp tiny_fixture?(event) do
    if Map.get(event, :allow_tiny_fixture?) in [true, "true"],
      do: :ok,
      else: {:error, :raw_tensor_arrays_forbidden}
  end

  defp tensor_like_array?(value) when is_list(value), do: numeric_nested?(value)
  defp tensor_like_array?(_value), do: false

  defp numeric_nested?(values) when is_list(values) do
    Enum.any?(values) and
      Enum.all?(values, fn value -> is_number(value) or numeric_nested?(value) end)
  end

  defp numeric_nested?(_value), do: false

  defp normalize_keys(event), do: SafeTerms.normalize_keys(event)
end
