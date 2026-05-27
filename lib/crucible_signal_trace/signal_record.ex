defmodule CrucibleSignalTrace.SignalRecord do
  @moduledoc """
  Trace record for one signal ref and its bounded summary.
  """

  alias CrucibleSignal.SignalRef

  @derive Jason.Encoder
  defstruct signal_ref: nil,
            summary: nil,
            value_ref: nil,
            capture_mode: :summary,
            recorded_at: nil,
            metadata: %{}

  @type t :: %__MODULE__{}

  def new(attrs) when is_list(attrs) or is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, signal_ref} <- normalize_ref(Map.get(attrs, :signal_ref)) do
      {:ok,
       %__MODULE__{
         signal_ref: signal_ref,
         summary: Map.get(attrs, :summary),
         value_ref: Map.get(attrs, :value_ref),
         capture_mode: Map.get(attrs, :capture_mode, signal_ref.capture_mode),
         recorded_at: Map.get(attrs, :recorded_at, DateTime.utc_now()),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  def new!(attrs) do
    case new(attrs) do
      {:ok, record} -> record
      {:error, reason} -> raise ArgumentError, "invalid signal record: #{inspect(reason)}"
    end
  end

  defp normalize_ref(%SignalRef{} = ref), do: {:ok, ref}
  defp normalize_ref(attrs) when is_list(attrs) or is_map(attrs), do: SignalRef.new(attrs)
  defp normalize_ref(nil), do: {:error, {:missing_required_fields, [:signal_ref]}}
  defp normalize_ref(other), do: {:error, {:invalid_signal_ref, other}}

  defp normalize_attrs(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize_attrs()

  defp normalize_attrs(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
