defmodule CrucibleSignalTrace.Validate do
  @moduledoc """
  Strict V4 trace event validation.
  """

  @schema_version "crucible.trace.v4"

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
    event = normalize_keys(event)

    with :ok <- require_base(event),
         :ok <- validate_schema(event),
         :ok <- validate_type(event),
         :ok <- validate_no_raw_arrays(event) do
      event
    else
      {:error, reason} -> raise ArgumentError, "invalid v4 trace event: #{inspect(reason)}"
    end
  end

  def validate_event!(event),
    do: raise(ArgumentError, "expected event map, got: #{inspect(event)}")

  def validate_event(event) when is_map(event) do
    {:ok, validate_event!(event)}
  rescue
    error in ArgumentError -> {:error, error.message}
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

  defp normalize_keys(event) do
    Map.new(event, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), normalize_nested(value)}
      {key, value} -> {key, normalize_nested(value)}
    end)
  end

  defp normalize_nested(value) when is_map(value), do: normalize_keys(value)
  defp normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  defp normalize_nested(value), do: value
end
