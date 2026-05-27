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
        model_ref: "qwen3:fixture",
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
  end

  defp signal_ref(signal_type, signal_id) do
    SignalRef.new!(
      trace_id: "trace-1",
      signal_id: signal_id,
      signal_type: signal_type,
      model_ref: "qwen3:fixture",
      dtype: :f32,
      shape: {1, 3}
    )
  end
end
