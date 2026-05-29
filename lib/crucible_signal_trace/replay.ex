defmodule CrucibleSignalTrace.Replay do
  @moduledoc """
  Load, validate, filter, and negotiate against recorded traces without a live provider.

  Replay operates on canonical `Crucible.ForwardTrace` artifacts produced by
  `CrucibleSignalTrace.Ingest` or checked-in JSONL fixtures. It derives a
  replay surface from recorded signal evidence and reuses `Crucible.CapabilityReport`
  negotiation semantics for tap-plan matching.
  """

  alias Crucible.CapabilityReport
  alias Crucible.ForwardTrace
  alias Crucible.SignalRecord
  alias CrucibleSignalTrace.{Ingest, Validate}
  alias CrucibleTap.{Surface, SurfaceNode, TapPlan}

  @type filter :: %{
          optional(:signal_type) => atom() | String.t() | [atom() | String.t()],
          optional(:tap_id) => String.t() | [String.t()],
          optional(:token_index) => integer() | [integer()],
          optional(:layer_index) => integer() | [integer()]
        }

  @doc """
  Loads a completed trace from JSONL and marks it as replay evidence.

  Options:

    * `:validate` — validation level passed to `Validate.validate_forward_trace/2`
      (default `:shape`)
    * `:skip_validate` — when true, skip validation (default false)
  """
  @spec load(String.t(), keyword()) :: {:ok, ForwardTrace.t()} | {:error, term()}
  def load(path, opts \\ []) when is_binary(path) do
    with {:ok, trace} <- Ingest.from_jsonl(path, opts),
         :ok <- maybe_validate(trace, opts) do
      {:ok, mark_replay(trace, path)}
    end
  end

  @spec load!(String.t(), keyword()) :: ForwardTrace.t()
  def load!(path, opts \\ []) when is_binary(path) do
    case load(path, opts) do
      {:ok, trace} ->
        trace

      {:error, reason} ->
        raise ArgumentError, "replay load failed for #{path}: #{inspect(reason)}"
    end
  end

  @doc "Loads all JSONL traces under a directory."
  @spec load_directory(String.t(), keyword()) :: {:ok, [ForwardTrace.t()]} | {:error, term()}
  def load_directory(directory, opts \\ []) when is_binary(directory) do
    with {:ok, traces} <- Ingest.from_directory(directory, opts) do
      validated =
        Enum.reduce_while(traces, [], fn trace, acc ->
          case maybe_validate(trace, opts) do
            :ok -> {:cont, [mark_replay(trace, directory) | acc]}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)

      case validated do
        {:error, _} = error -> error
        traces -> {:ok, Enum.reverse(traces)}
      end
    end
  end

  @doc "Returns replay metadata describing provenance for a loaded trace."
  @spec replay_metadata(ForwardTrace.t()) :: map()
  def replay_metadata(%ForwardTrace{} = trace) do
    Map.get(trace.metadata, :replay, %{})
  end

  @doc "Derives a replay surface from recorded signal evidence."
  @spec surface(ForwardTrace.t()) :: Surface.t()
  def surface(%ForwardTrace{} = trace) do
    nodes =
      trace.signals
      |> Enum.map(&surface_node/1)
      |> Enum.uniq_by(& &1.id)

    Surface.new!(%{
      adapter: :replay,
      model_family: trace.model_family,
      nodes: nodes,
      metadata: %{
        trace_id: trace.trace_id,
        provider_kind: trace.provider_kind,
        replay: true
      }
    })
  end

  @doc """
  Filters recorded signals by canonical replay selectors.

  Supported filter keys: `:signal_type`, `:tap_id`, `:token_index`, `:layer_index`.
  """
  @spec filter_signals(ForwardTrace.t(), filter()) :: [SignalRecord.t()]
  def filter_signals(%ForwardTrace{} = trace, filter) when is_map(filter) do
    Enum.filter(trace.signals, &matches_filter?(&1, filter))
  end

  @doc """
  Negotiates a tap plan against replay evidence derived from the trace.

  Required taps absent from the recorded trace fail closed via the standard
  capability report path. Optional taps degrade with explicit reasons.
  """
  @spec negotiate(ForwardTrace.t(), TapPlan.t(), keyword()) ::
          {:ok, CrucibleTap.CompiledPlan.t(), CapabilityReport.t()}
          | {:error, {:tap_compile_failed, CapabilityReport.t()}}
  def negotiate(%ForwardTrace{} = trace, %TapPlan{} = tap_plan, opts \\ []) do
    CapabilityReport.negotiate(
      tap_plan,
      surface(trace),
      Keyword.merge(
        [
          provider_kind: :replay,
          model_id: trace.model_id,
          backend: trace.backend
        ],
        opts
      )
    )
  end

  defp surface_node(%SignalRecord{} = signal) do
    SurfaceNode.new!(%{
      id: signal.tap_id || signal.signal_id || node_id(signal),
      signal_type: signal.signal_type,
      layer_name: signal.node_name,
      layer_index: signal.layer_index,
      token_index: signal.token_index,
      operations: [:read],
      capture_modes: capture_modes(signal),
      metadata: %{
        signal_id: signal.signal_id,
        tap_id: signal.tap_id,
        capture_method: signal.capture_method
      }
    })
  end

  defp node_id(%SignalRecord{signal_type: type, layer_index: layer, token_index: token}) do
    parts =
      [type, layer, token]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)

    Enum.join(parts, ":")
  end

  defp capture_modes(%SignalRecord{tensor_summary: summary}) when not is_nil(summary),
    do: [:summary]

  defp capture_modes(_signal), do: [:summary]

  defp matches_filter?(signal, filter) do
    Enum.all?(filter, fn {key, value} -> matches_field?(signal, key, value) end)
  end

  defp matches_field?(signal, :signal_type, value) do
    allowed = List.wrap(value) |> Enum.map(&atomize/1)
    signal.signal_type in allowed
  end

  defp matches_field?(signal, :tap_id, value),
    do: signal.tap_id in List.wrap(value)

  defp matches_field?(signal, :token_index, value),
    do: signal.token_index in List.wrap(value)

  defp matches_field?(signal, :layer_index, value),
    do: signal.layer_index in List.wrap(value)

  defp matches_field?(_signal, _key, _value), do: true

  defp maybe_validate(trace, opts) do
    if Keyword.get(opts, :skip_validate, false) do
      :ok
    else
      level = Keyword.get(opts, :validate, :shape)
      Validate.validate_forward_trace(trace, level)
    end
  end

  defp mark_replay(trace, source) do
    replay_meta = %{
      origin: :replay,
      source: source,
      replayed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    %{trace | metadata: Map.put(trace.metadata, :replay, replay_meta)}
  end

  defp atomize(value) when is_atom(value), do: value
  defp atomize(value) when is_binary(value), do: String.to_atom(value)
  defp atomize(value), do: value
end
