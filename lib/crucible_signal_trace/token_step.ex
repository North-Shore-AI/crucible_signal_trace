defmodule CrucibleSignalTrace.TokenStep do
  @moduledoc """
  Typed low-level token-boundary event emitted during generation or replay.
  """

  alias CrucibleSignalTrace.SafeTerms

  @derive Jason.Encoder
  defstruct trace_id: nil,
            token_index: nil,
            logits_ref: nil,
            steering: %{},
            generated_token_id: nil,
            generated_token_text: nil,
            entropy: nil,
            margin: nil,
            top_k: [],
            metadata: %{}

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    attrs = SafeTerms.normalize_keys(attrs)

    with :ok <- require_fields(attrs, [:trace_id, :token_index]) do
      {:ok,
       %__MODULE__{
         trace_id: Map.fetch!(attrs, :trace_id),
         token_index: Map.fetch!(attrs, :token_index),
         logits_ref: Map.get(attrs, :logits_ref),
         steering: Map.get(attrs, :steering, %{}),
         generated_token_id: Map.get(attrs, :generated_token_id, Map.get(attrs, :token_id)),
         generated_token_text: Map.get(attrs, :generated_token_text, Map.get(attrs, :token_text)),
         entropy: Map.get(attrs, :entropy),
         margin: Map.get(attrs, :margin),
         top_k: Map.get(attrs, :top_k, []),
         metadata: Map.get(attrs, :metadata, %{})
       }}
    end
  end

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, step} -> step
      {:error, reason} -> raise ArgumentError, "invalid token step: #{inspect(reason)}"
    end
  end

  defp require_fields(attrs, fields) do
    missing = Enum.reject(fields, &(Map.get(attrs, &1) not in [nil, ""]))
    if missing == [], do: :ok, else: {:error, {:missing_required_fields, missing}}
  end
end
