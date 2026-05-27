defmodule CrucibleSignalTrace.LayerTrajectory do
  @moduledoc """
  Ordered layer trajectory summaries for a forward pass.
  """

  @derive Jason.Encoder
  defstruct points: [], metadata: %{}

  @type point :: %{
          required(:layer_index) => integer() | :embedding | :final,
          optional(:token_index) => integer(),
          optional(:signal_ref) => String.t(),
          optional(:norm) => number(),
          optional(:drift) => number(),
          optional(:metadata) => map()
        }

  @type t :: %__MODULE__{points: [point()]}

  def new(points, attrs \\ []) when is_list(points) do
    {:ok,
     %__MODULE__{
       points: Enum.map(points, &normalize_point/1),
       metadata: Keyword.get(attrs, :metadata, %{})
     }}
  end

  def new!(points, attrs \\ []) do
    {:ok, trajectory} = new(points, attrs)
    trajectory
  end

  def ordered_layers(%__MODULE__{} = trajectory) do
    Enum.map(trajectory.points, &Map.fetch!(&1, :layer_index))
  end

  defp normalize_point(point) when is_list(point), do: point |> Map.new() |> normalize_point()

  defp normalize_point(point) when is_map(point) do
    Map.new(point, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
