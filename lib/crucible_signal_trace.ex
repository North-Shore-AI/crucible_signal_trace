defmodule CrucibleSignalTrace do
  @moduledoc """
  Bounded forward-pass trace schema for Crucible signal captures.

  This package records signal refs, layer trajectories, decode telemetry, and
  bounded summaries without requiring raw tensor materialization.
  """

  @version Mix.Project.config()[:version]

  @doc "Returns the package version."
  def version, do: @version

  @doc "Builds a canonical forward trace."
  defdelegate forward_trace!(attrs), to: Crucible.ForwardTrace, as: :new!

  @doc "Validates a completed forward trace at the requested level."
  defdelegate validate_forward_trace(trace, level \\ :shape),
    to: CrucibleSignalTrace.Validate

  @doc "Loads a trace artifact for replay without a live provider."
  defdelegate replay_load(path, opts \\ []), to: CrucibleSignalTrace.Replay, as: :load
end
