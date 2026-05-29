defmodule CrucibleSignalTrace.FixtureTraceTest do
  use ExUnit.Case, async: true

  alias CrucibleSignalTrace.{Ingest, JSONL, Validate}

  @fixture_path Path.join(__DIR__, "fixtures/minimal_forward_trace.jsonl")

  test "checked-in minimal_forward_trace.jsonl ingests to ForwardTrace (PATCH-TRACE-001)" do
    assert File.exists?(@fixture_path)

    assert {:ok, %Crucible.ForwardTrace{} = trace} = Ingest.from_jsonl(@fixture_path)

    assert trace.trace_id == "trace-fixture-minimal"
    assert trace.run_id == "run-fixture-minimal"
    assert trace.provider_kind == :fixture
    assert trace.model_id == "model:fixture"
    assert trace.model_family == :example_transformer
    assert trace.backend == :fixture
    assert trace.status == :ok

    assert [%Crucible.SignalRecord{signal_type: :final_logits, signal_id: "sig-fixture-final"}] =
             trace.signals

    assert String.starts_with?(trace.metadata.trace_digest, "sha256:")
  end

  test "fixture JSONL events validate and roundtrip through re-encode" do
    events = @fixture_path |> JSONL.stream!() |> Enum.to_list()

    assert Enum.map(events, &event_type/1) == ["trace_start", "signal_record", "trace_end"]
    assert Enum.all?(events, &match?(%{}, Validate.validate_event!(&1)))

    {:ok, trace} = Ingest.from_jsonl(@fixture_path)

    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_fixture_roundtrip_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    File.write!(path, "")

    JSONL.write_event!(
      path,
      JSONL.v4_event(:trace_start,
        trace_id: trace.trace_id,
        run_id: trace.run_id,
        provider_kind: trace.provider_kind,
        model_id: trace.model_id,
        model_family: trace.model_family,
        backend: trace.backend
      )
    )

    for signal <- trace.signals do
      JSONL.write_event!(
        path,
        JSONL.v4_event(:signal_record, trace_id: trace.trace_id, signal: signal)
      )
    end

    JSONL.write_event!(
      path,
      JSONL.v4_event(:trace_end, trace_id: trace.trace_id, status: trace.status)
    )

    assert {:ok, roundtrip} = Ingest.from_jsonl(path)
    assert roundtrip.trace_id == trace.trace_id
    assert length(roundtrip.signals) == length(trace.signals)
  end

  defp event_type(event) do
    Map.get(event, :event_type) || Map.get(event, "event_type")
  end
end
