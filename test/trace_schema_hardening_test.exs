defmodule CrucibleSignalTrace.TraceSchemaHardeningTest do
  use ExUnit.Case, async: true

  alias CrucibleSignalTrace.{Ingest, JSONL, Replay, TokenStep, TraceFragment, Validate}

  @fixture Path.join(__DIR__, "fixtures/replay_token_step_trace.jsonl")

  test "canonical event vocabulary accepts token_step writes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_token_step_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    event = JSONL.token_step("trace-token", 0, "logits:0", %{mode: "test"})

    assert "token_step" in Validate.event_types()
    assert %{event_type: "token_step"} = JSONL.write_event!(path, event)
    assert [%{"event_type" => "token_step"}] = JSONL.stream!(path) |> Enum.to_list()
  end

  test "token steps and trace fragments have typed constructors" do
    event = JSONL.token_step("trace-fragment", 0, "logits:0", %{mode: "test"})

    assert %TokenStep{trace_id: "trace-fragment", token_index: 0, logits_ref: "logits:0"} =
             TokenStep.new!(event)

    fragment =
      TraceFragment.new!(
        trace_id: "trace-fragment",
        ordinal: 1,
        source: "test",
        events: [JSONL.v4_event(:trace_start, trace_id: "trace-fragment"), event]
      )

    assert fragment.event_count == 2
    assert [%{event_type: "trace_start"}, %{event_type: "token_step"}] = fragment.events
  end

  test "event and replay validation levels reject malformed replay evidence" do
    assert {:ok, trace} = Ingest.from_jsonl(@fixture)

    assert :ok = Validate.validate_forward_trace(trace, :events)
    assert :ok = Validate.validate_forward_trace(trace, :replay)
    assert [%TokenStep{token_index: 0, logits_ref: "sig-token-step-final"}] = trace.decoding_steps

    mismatched = %{trace | events: [JSONL.v4_event(:trace_start, trace_id: "other-trace")]}

    assert {:error, {:event_trace_id_mismatch, "trace-token-step-fixture", "other-trace"}} =
             Validate.validate_forward_trace(mismatched, :events)

    missing_report = %{trace | capability_report: nil}

    assert {:error, :missing_capability_report} =
             Validate.validate_forward_trace(missing_report, :replay)
  end

  test "replay load supports replay validation level" do
    assert {:ok, trace} = Replay.load(@fixture, validate: :replay)

    assert trace.trace_id == "trace-token-step-fixture"
    assert trace.metadata.replay.origin == :replay
  end

  test "external JSON keys are not converted into new atoms" do
    external_key = "external_key_#{System.unique_integer([:positive])}"

    refute existing_atom?(external_key)

    event = %{
      "event_type" => "token_step",
      "trace_id" => "trace-external-key",
      "schema_version" => Validate.schema_version(),
      "token_index" => 0,
      "logits_ref" => "logits:0",
      external_key => "top-level",
      "metadata" => %{external_key => "nested"}
    }

    assert {:ok, validated} = Validate.validate_event(event)
    assert Map.fetch!(validated, external_key) == "top-level"
    assert Map.fetch!(validated.metadata, external_key) == "nested"
    refute existing_atom?(external_key)
  end

  defp existing_atom?(value) do
    _ = String.to_existing_atom(value)
    true
  rescue
    ArgumentError -> false
  end
end
