alias CrucibleSignal.SignalRef
alias CrucibleSignalTrace.{ForwardTrace, JSONL, LayerTrajectory}

trace =
  ForwardTrace.new!(
    trace_id: "trace-jsonl-example",
    model_ref: "model:fixture",
    layer_trajectory:
      LayerTrajectory.new!([
        %{layer_index: 4, vector: [1.0, 0.0]},
        %{layer_index: 8, vector: [0.0, 1.0]}
      ]),
    final_logits: SignalRef.for_final_logits(trace_id: "trace-jsonl-example")
  )

path = Path.join(System.tmp_dir!(), "trace-jsonl-example.jsonl")

events = [
  JSONL.trace_start(trace.trace_id),
  JSONL.trace_end(trace.trace_id, %{digest: ForwardTrace.digest(trace)})
]

:ok = JSONL.stream_encode(path, events)
decoded_count = JSONL.stream_decode(path) |> Enum.count()
File.rm(path)

IO.puts(Jason.encode!(%{ok: true, example: "trace_jsonl_mock", events: decoded_count}))
