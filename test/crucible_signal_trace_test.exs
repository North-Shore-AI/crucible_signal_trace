defmodule CrucibleSignalTraceTest do
  use ExUnit.Case
  doctest CrucibleSignalTrace

  alias CrucibleSignal.{SignalRef, TensorSummary}

  alias CrucibleSignalTrace.{
    Digest,
    ForwardTrace,
    JSONL,
    LayerTrajectory,
    Redactor,
    SignalRecord,
    TraceEvent
  }

  test "exposes package version" do
    assert CrucibleSignalTrace.version() == "0.1.0"
  end

  test "builds signal records and forward traces without raw tensors" do
    logits_ref = signal_ref(:final_logits, "logits")
    hidden_ref = signal_ref(:middle_residuals, "hidden")

    record =
      SignalRecord.new!(
        signal_ref: hidden_ref,
        summary: TensorSummary.summarize([1.0, 2.0, 3.0]),
        metadata: %{layer: 12}
      )

    trajectory =
      LayerTrajectory.new!([
        %{layer_index: :embedding, signal_ref: "embedding", norm: 1.0},
        %{layer_index: 12, signal_ref: "hidden", norm: 3.0},
        %{layer_index: :final, signal_ref: "logits", norm: 5.0}
      ])

    trace =
      ForwardTrace.new!(
        trace_id: "trace-1",
        model_ref: "model:fixture",
        input_hash: Digest.text("hello"),
        tap_plan_ref: "tap-plan-1",
        signal_records: [record],
        layer_trajectory: trajectory,
        final_logits: logits_ref,
        cache_summary: %{blocks: 2}
      )
      |> ForwardTrace.complete()

    assert trace.final_logits.signal_id == "logits"
    assert trace.cache_summary == %{blocks: 2}
    assert LayerTrajectory.ordered_layers(trace.layer_trajectory) == [:embedding, 12, :final]
    assert is_binary(ForwardTrace.digest(trace))
  end

  test "serializes traces to JSONL" do
    trace =
      CrucibleSignalTrace.forward_trace!(
        trace_id: "trace-json",
        model_ref: "model",
        signal_records: [
          [
            signal_ref: signal_ref(:embeddings, "embedding"),
            summary: TensorSummary.summarize([1, 2, 3])
          ]
        ]
      )

    line = JSONL.encode_line!(trace)

    assert {:ok, decoded} = JSONL.decode_line(line)
    assert decoded["trace_id"] == "trace-json"
    assert [%{"signal_ref" => %{"signal_type" => "embeddings"}}] = decoded["signal_records"]
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
    trace = ForwardTrace.new!(trace_id: "trace-export", model_ref: "model")

    event = CrucibleSignalTrace.Export.AITrace.event(trace)

    assert event.name == "crucible.forward_trace"
    assert event.attributes.model_ref == "model"
    assert event.attributes.signal_count == 0

    assert {:ok, evidence} = CrucibleSignalTrace.Export.AITrace.to_evidence(trace)
    assert evidence.schema == "crucible.aitrace.evidence"
    assert evidence.version == 1
    assert evidence.trace_id == "trace-export"
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

    signal = %Crucible.SignalRecord{
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
    }

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
