defmodule CrucibleSignalTrace.DecodingStep do
  @moduledoc """
  Bounded telemetry for one decode step.
  """

  @derive Jason.Encoder
  defstruct step_index: nil,
            token_id: nil,
            token: nil,
            logits_ref: nil,
            entropy: nil,
            margin: nil,
            selected?: false,
            metadata: %{}

  @type t :: %__MODULE__{}
end
