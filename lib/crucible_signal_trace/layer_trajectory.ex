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
          optional(:vector) => [number()],
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

  def norm_curve(%__MODULE__{} = trajectory) do
    Enum.map(trajectory.points, fn point ->
      {Map.fetch!(point, :layer_index),
       Map.get(point, :norm) || vector_norm(Map.get(point, :vector))}
    end)
  end

  def cosine_drifts(%__MODULE__{} = trajectory) do
    trajectory.points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce_while({:ok, []}, fn [left, right], {:ok, acc} ->
      with {:ok, left_vector} <- fetch_vector(left),
           {:ok, right_vector} <- fetch_vector(right),
           {:ok, distance} <- cosine_distance(left_vector, right_vector) do
        {:cont,
         {:ok, [%{from: left.layer_index, to: right.layer_index, distance: distance} | acc]}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      {:error, reason} -> {:error, reason}
    end
  end

  def anomaly_flags(%__MODULE__{} = trajectory, opts \\ []) do
    threshold = Keyword.get(opts, :drift_threshold, 0.4)

    case cosine_drifts(trajectory) do
      {:ok, drifts} ->
        Enum.map(drifts, fn drift ->
          Map.put(drift, :anomaly?, drift.distance >= threshold)
        end)

      {:error, _reason} ->
        []
    end
  end

  defp normalize_point(point) when is_list(point), do: point |> Map.new() |> normalize_point()

  defp normalize_point(point) when is_map(point) do
    Map.new(point, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp fetch_vector(%{vector: vector}) when is_list(vector),
    do: {:ok, Enum.map(vector, &(&1 * 1.0))}

  defp fetch_vector(_point), do: {:error, :insufficient_data}

  defp cosine_distance(left, right) when length(left) == length(right) do
    left_norm = vector_norm(left)
    right_norm = vector_norm(right)

    if left_norm == 0.0 or right_norm == 0.0 do
      {:error, :zero_norm}
    else
      dot = Enum.zip_with(left, right, &(&1 * &2)) |> Enum.sum()
      {:ok, 1.0 - dot / (left_norm * right_norm)}
    end
  end

  defp cosine_distance(_left, _right), do: {:error, :shape_mismatch}

  defp vector_norm(nil), do: nil

  defp vector_norm(vector) when is_list(vector) do
    vector
    |> Enum.map(&(&1 * &1))
    |> Enum.sum()
    |> :math.sqrt()
  end
end
