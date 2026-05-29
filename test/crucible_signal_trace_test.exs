defmodule CrucibleSignalTraceTest do
  use ExUnit.Case
  doctest CrucibleSignalTrace

  alias CrucibleSignal.SignalRef

  alias CrucibleSignalTrace.{
    Digest,
    JSONL,
    LayerTrajectory,
    Redactor,
    TraceEvent
  }

  test "exposes package version" do
    assert CrucibleSignalTrace.version() == "0.1.0"
  end

  test "builds signal records and forward traces without raw tensors" do
    logits_ref = signal_ref(:final_logits, "logits")
    hidden_ref = signal_ref(:middle_residuals, "hidden")

    record =
      Crucible.SignalRecord.new!(
        signal_id: hidden_ref.signal_id,
        trace_id: hidden_ref.trace_id,
        signal_type: hidden_ref.signal_type,
        model_id: hidden_ref.model_ref,
        dtype: hidden_ref.dtype,
        shape: hidden_ref.shape.dims,
        rank: hidden_ref.shape.rank,
        layer_index: hidden_ref.layer_index,
        token_index: hidden_ref.token_index,
        capture_method: hidden_ref.capture_mode,
        tensor_summary: Crucible.TensorSummary.compute([1.0, 2.0, 3.0]),
        metadata: %{layer: 12}
      )

    trajectory =
      LayerTrajectory.new!([
        %{layer_index: :embedding, signal_ref: "embedding", norm: 1.0},
        %{layer_index: 12, signal_ref: "hidden", norm: 3.0},
        %{layer_index: :final, signal_ref: "logits", norm: 5.0}
      ])

    trace =
      Crucible.ForwardTrace.new!(
        trace_id: "trace-1",
        model_id: "model:fixture",
        input_hash: Digest.text("hello"),
        tap_plan_ref: "tap-plan-1",
        signals: [record],
        layer_trajectory: trajectory,
        final_logits: logits_ref,
        cache_summary: %{blocks: 2}
      )
      |> Crucible.ForwardTrace.complete()

    assert trace.final_logits.signal_id == "logits"
    assert trace.cache_summary == %{blocks: 2}
    assert LayerTrajectory.ordered_layers(trace.layer_trajectory) == [:embedding, 12, :final]
    assert is_binary(Crucible.ForwardTrace.digest(trace))
  end

  test "validate_forward_trace accepts bounded completed traces at shape level" do
    trace =
      Crucible.ForwardTrace.new!(
        trace_id: "trace-validate",
        provider_kind: :fixture,
        model_id: "model:fixture",
        signals: [
          Crucible.SignalRecord.new!(
            signal_id: "logits",
            trace_id: "trace-validate",
            signal_type: :final_logits,
            model_id: "model:fixture"
          )
        ]
      )

    assert :ok = CrucibleSignalTrace.validate_forward_trace(trace, :shape)
  end

  test "validate_forward_trace rejects traces with missing required fields" do
    trace = %Crucible.ForwardTrace{trace_id: "trace-missing", signals: []}

    assert {:error, {:missing_trace_fields, fields}} =
             CrucibleSignalTrace.Validate.validate_forward_trace(trace, :shape)

    assert :provider_kind in fields
    assert :model_id in fields

    assert {:error, :empty_signals} =
             CrucibleSignalTrace.Validate.validate_forward_trace(
               %Crucible.ForwardTrace{
                 trace_id: "trace-empty",
                 provider_kind: :fixture,
                 model_id: "model:fixture",
                 signals: []
               },
               :shape
             )
  end

  test "serializes traces to JSONL" do
    signal =
      Crucible.SignalRecord.new!(
        signal_id: "embedding",
        trace_id: "trace-json",
        signal_type: :embeddings,
        model_id: "model",
        tensor_summary: Crucible.TensorSummary.compute([1, 2, 3])
      )

    trace =
      CrucibleSignalTrace.forward_trace!(
        trace_id: "trace-json",
        model_id: "model",
        signals: [signal]
      )

    line = JSONL.encode_line!(trace)

    assert {:ok, decoded} = JSONL.decode_line(line)
    assert decoded["trace_id"] == "trace-json"
    assert [%{"signal_type" => "embeddings"}] = decoded["signals"]
  end

  test "streams JSONL event envelopes" do
    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_stream_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    events = [
      JSONL.trace_start("trace-stream"),
      JSONL.token_step("trace-stream", 0, "logits:0"),
      JSONL.trace_end("trace-stream")
    ]

    assert :ok = JSONL.stream_encode(path, events)

    decoded =
      path
      |> JSONL.stream_decode()
      |> Enum.map(fn {:ok, value} -> value["event_type"] end)

    assert decoded == ["trace_start", "token_step", "trace_end"]
  end

  test "computes layer-to-layer cosine drift from vectors" do
    trajectory =
      LayerTrajectory.new!([
        %{layer_index: 12, vector: [1.0, 0.0, 0.0]},
        %{layer_index: 16, vector: [0.0, 1.0, 0.0]},
        %{layer_index: 20, vector: [0.0, 1.0, 0.0]}
      ])

    assert {:ok, [%{from: 12, to: 16, distance: first}, %{from: 16, to: 20, distance: second}]} =
             LayerTrajectory.cosine_drifts(trajectory)

    assert_in_delta first, 1.0, 0.001
    assert_in_delta second, 0.0, 0.001
    assert [{12, 1.0}, {16, 1.0}, {20, 1.0}] = LayerTrajectory.norm_curve(trajectory)

    assert [%{anomaly?: true}, %{anomaly?: false}] =
             LayerTrajectory.anomaly_flags(trajectory, drift_threshold: 0.5)
  end

  test "cosine drift errors without vectors" do
    trajectory =
      LayerTrajectory.new!([
        %{layer_index: 1, norm: 1.0},
        %{layer_index: 2, norm: 2.0}
      ])

    assert {:error, :insufficient_data} = LayerTrajectory.cosine_drifts(trajectory)
  end

  test "appends JSONL files" do
    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    event = TraceEvent.new!(trace_id: "trace-1", event_type: "forward.completed")

    assert :ok = JSONL.append(path, event)
    assert {:ok, decoded} = path |> File.read!() |> JSONL.decode_line()
    assert decoded["event_type"] == "forward.completed"
  end

  test "redacts oversize strings with digest and preview" do
    redacted = Redactor.bounded(String.duplicate("a", 20), limit: 5)

    assert redacted.preview == "aaaaa"
    assert redacted.byte_size == 20
    assert is_binary(redacted.sha256)
  end

  test "builds AITrace-compatible export event payload" do
    trace = Crucible.ForwardTrace.new!(trace_id: "trace-export", model_id: "model")

    event = CrucibleSignalTrace.Export.AITrace.event(trace)

    assert event.name == "crucible.forward_trace"
    assert event.attributes.model_ref == "model"
    assert event.attributes.signal_count == 0

    assert {:ok, evidence} = CrucibleSignalTrace.Export.AITrace.to_evidence(trace)
    assert evidence.schema == "crucible.aitrace.evidence"
    assert evidence.version == 1
    assert evidence.trace_id == "trace-export"
  end

  test "loads checked-in minimal fixture and roundtrips JSON and JSONL" do
    json_path = Path.join(__DIR__, "fixtures/minimal_forward_trace.json")
    jsonl_path = Path.join(__DIR__, "fixtures/minimal_forward_trace.jsonl")

    {:ok, decoded} = json_path |> File.read!() |> Jason.decode()
    assert decoded["trace_id"] == "trace-fixture-minimal"

    trace_from_json =
      decoded
      |> Crucible.ForwardTrace.new!()
      |> Crucible.ForwardTrace.complete()

    assert trace_from_json.provider_kind in [:fixture, "fixture"]
    assert [%Crucible.SignalRecord{signal_id: "sig-fixture-final"}] = trace_from_json.signals

    reencoded = JSONL.encode_line!(trace_from_json)
    assert {:ok, roundtrip} = JSONL.decode_line(reencoded)
    assert roundtrip["trace_id"] == "trace-fixture-minimal"

    assert {:ok, ingested} = CrucibleSignalTrace.Ingest.from_jsonl(jsonl_path)
    assert ingested.trace_id == "trace-fixture-minimal"
    assert ingested.status == :ok
    assert [%Crucible.SignalRecord{signal_type: :final_logits}] = ingested.signals
    assert is_binary(ingested.metadata.trace_digest)
  end

  test "writes, validates, and ingests V4 JSONL events" do
    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_v4_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    trace_id = "trace-v4"
    summary = Crucible.TensorSummary.compute([1.0, 2.0, 3.0], entropy: true, top_k: 2)

    signal =
      Crucible.SignalRecord.new!(
        signal_id: "sig-v4",
        trace_id: trace_id,
        run_id: "run-v4",
        signal_type: :final_logits,
        provider_kind: :elixir_bumblebee,
        model_id: "hf-internal-testing/tiny-random-gpt2",
        model_family: :gpt2,
        backend: :exla_cpu,
        node_name: "final_logits",
        capture_method: :axon_hook,
        tensor_summary: summary
      )

    JSONL.write_event!(
      path,
      JSONL.v4_event(:trace_start,
        trace_id: trace_id,
        run_id: "run-v4",
        provider_kind: :elixir_bumblebee,
        model_id: "hf-internal-testing/tiny-random-gpt2",
        model_family: :gpt2,
        backend: :exla_cpu
      )
    )

    JSONL.write_event!(path, JSONL.v4_event(:signal_record, trace_id: trace_id, signal: signal))
    JSONL.write_event!(path, JSONL.v4_event(:trace_end, trace_id: trace_id, status: :ok))

    assert [%{"event_type" => "signal_record"}] =
             path
             |> JSONL.stream!()
             |> Enum.filter(&(&1["event_type"] == "signal_record"))

    assert {:ok, %Crucible.ForwardTrace{} = trace} = CrucibleSignalTrace.Ingest.from_jsonl(path)
    assert trace.trace_id == trace_id
    assert [%Crucible.SignalRecord{signal_type: :final_logits}] = trace.signals
    assert trace.status == :ok
    assert String.starts_with?(trace.metadata.trace_digest, "sha256:")
  end

  test "validates every V5 matrix, blocker, backend, policy, and route event" do
    trace_id = "trace-v5-events"

    events = [
      JSONL.v4_event(:backend_event, trace_id: trace_id, backend: :binary, duration_ms: 12),
      JSONL.matrix_row(trace_id, :model, %{model_id: "gpt2", forward_ok: true}),
      JSONL.matrix_row(trace_id, :backend, %{backend: "binary", forward_ok: true}),
      JSONL.matrix_row(trace_id, :signal, %{signal: "hidden_state", status: "unsupported"}),
      JSONL.matrix_row(trace_id, :generation, %{steps: 8, status: "generation_tokens"}),
      JSONL.capability_blocker(trace_id, :hidden_state, :blocked_by_bumblebee_api),
      JSONL.v4_event(:policy_decision, trace_id: trace_id, decision: %{selected_action: :worker}),
      JSONL.v4_event(:route_decision, trace_id: trace_id, route: %{role_id: "Worker"})
    ]

    assert Enum.all?(events, &match?(%{}, CrucibleSignalTrace.Validate.validate_event!(&1)))
    assert "signal_matrix_row" in CrucibleSignalTrace.Validate.event_types()
  end

  test "ingests a directory of real native trace JSONL files" do
    root =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_dir_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    for index <- 1..2 do
      path = Path.join(root, "trace_#{index}.jsonl")
      trace_id = "trace-dir-#{index}"

      JSONL.write_event!(path, JSONL.v4_event(:trace_start, trace_id: trace_id, model_id: "gpt2"))
      JSONL.write_event!(path, JSONL.v4_event(:trace_end, trace_id: trace_id, status: :ok))
    end

    assert [
             %Crucible.ForwardTrace{trace_id: "trace-dir-1"},
             %Crucible.ForwardTrace{trace_id: "trace-dir-2"}
           ] =
             CrucibleSignalTrace.Ingest.from_directory!(root)
  end

  test "preserves V5 signal provenance during ingestion" do
    path =
      Path.join(
        System.tmp_dir!(),
        "crucible_signal_trace_v5_signal_#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    signal =
      Crucible.SignalRecord.new!(
        signal_id: "sig-v5",
        trace_id: "trace-v5-signal",
        signal_type: :final_logits,
        model_id: "gpt2",
        model_revision: "main",
        model_family: :gpt2,
        backend: :binary,
        dtype: :f32,
        shape: [1, 1, 50257],
        rank: 3,
        layer_index: :final,
        token_index: -1,
        node_name: "final_logits",
        capture_method: :axon_predict_output,
        surface_id: "gpt2-surface",
        tap_id: "final_logits",
        capability_status: :captured,
        tensor_summary: Crucible.TensorSummary.compute([1.0, 0.5, 0.0], entropy: true, top_k: 2)
      )

    JSONL.write_event!(path, JSONL.v4_event(:trace_start, trace_id: "trace-v5-signal"))

    JSONL.write_event!(
      path,
      JSONL.v4_event(:signal_record, trace_id: "trace-v5-signal", signal: signal)
    )

    JSONL.write_event!(path, JSONL.v4_event(:trace_end, trace_id: "trace-v5-signal", status: :ok))

    {:ok, trace} = CrucibleSignalTrace.Ingest.from_jsonl(path)
    [ingested] = trace.signals

    assert ingested.model_revision == "main"
    assert ingested.dtype == :f32
    assert ingested.shape == [1, 1, 50257]
    assert ingested.surface_id == "gpt2-surface"
    assert ingested.tap_id == "final_logits"
    assert ingested.capability_status == :captured
  end

  test "rejects V4 signal records with inline raw arrays" do
    event =
      JSONL.v4_event(:signal_record,
        trace_id: "trace-v4-bad",
        signal: %{signal_id: "bad", tensor: [1.0, 2.0, 3.0]}
      )

    assert_raise ArgumentError, ~r/raw_tensor_arrays_forbidden/, fn ->
      CrucibleSignalTrace.Validate.validate_event!(event)
    end
  end

  defp signal_ref(signal_type, signal_id) do
    SignalRef.new!(
      trace_id: "trace-1",
      signal_id: signal_id,
      signal_type: signal_type,
      model_ref: "model:fixture",
      dtype: :f32,
      shape: {1, 3}
    )
  end
end
