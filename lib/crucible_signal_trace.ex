defmodule CrucibleSignalTrace do
  @moduledoc """
  Bounded forward-pass trace schema for Crucible signal captures.

  This package records signal refs, layer trajectories, decode telemetry, and
  bounded summaries without requiring raw tensor materialization.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the package version."
  def version, do: @version

  @doc "Builds a forward trace."
  defdelegate forward_trace!(attrs), to: CrucibleSignalTrace.ForwardTrace, as: :new!
end
