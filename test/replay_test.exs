defmodule CrucibleSignalTrace.ReplayTest do
  use ExUnit.Case, async: true

  alias CrucibleSignalTrace.Replay
  alias CrucibleTap.TapPlan

  @fixture Path.expand("fixtures/minimal_forward_trace.jsonl", __DIR__)

  test "load/1 ingests fixture trace and marks replay metadata" do
    assert {:ok, trace} = Replay.load(@fixture)
    assert trace.trace_id == "trace-fixture-minimal"
    assert trace.metadata.replay.origin == :replay
    assert trace.metadata.replay.source == @fixture
    assert is_binary(trace.metadata.replay.replayed_at)
  end

  test "filter_signals/2 filters by signal_type" do
    trace = Replay.load!(@fixture)

    assert [%Crucible.SignalRecord{signal_type: :final_logits}] =
             Replay.filter_signals(trace, %{signal_type: :final_logits})

    assert Replay.filter_signals(trace, %{signal_type: :hidden_state}) == []
  end

  test "surface/1 derives replay nodes from recorded signals" do
    trace = Replay.load!(@fixture)
    surface = Replay.surface(trace)

    assert surface.adapter == :replay
    assert surface.metadata.replay == true
    assert length(surface.nodes) == 1
    assert hd(surface.nodes).signal_type == :final_logits
  end

  test "surface/1 preserves canonical activation metadata from recorded signals" do
    trace = activation_trace()
    surface = Replay.surface(trace)
    [node] = surface.nodes

    assert node.activation_name == "blocks.0.attn.hook_q"
    assert node.component == :attn
    assert node.axes == [:batch, :pos, :head, :d_head]
    assert node.layer_index == 0
  end

  test "filter_signals/2 filters by activation name and component" do
    trace = activation_trace()

    assert [%Crucible.SignalRecord{signal_id: "q0"}] =
             Replay.filter_signals(trace, %{activation_name: "blocks.0.attn.hook_q"})

    assert [%Crucible.SignalRecord{signal_id: "q0"}] =
             Replay.filter_signals(trace, %{component: :attn})

    assert Replay.filter_signals(trace, %{activation_name: "blocks.1.attn.hook_q"}) == []
  end

  test "negotiate/3 satisfies required final_logits tap against fixture trace" do
    trace = Replay.load!(@fixture)

    plan =
      TapPlan.new!(
        [
          [
            id: "final-logits",
            kind: :read,
            required?: true,
            signal_type: :final_logits
          ]
        ],
        plan_id: "replay-plan"
      )

    assert {:ok, compiled, report} = Replay.negotiate(trace, plan)
    assert compiled.report.matched != []
    assert report.required_missing == []
    assert report.failed == []
  end

  test "negotiate/3 fails closed when required tap is absent from trace" do
    trace = Replay.load!(@fixture)

    plan =
      TapPlan.new!(
        [[id: "hidden", kind: :read, required?: true, signal_type: :hidden_state]],
        plan_id: "replay-plan-hidden"
      )

    assert {:error, {:tap_compile_failed, report}} = Replay.negotiate(trace, plan)
    assert report.required_missing != [] or report.failed != []
  end

  test "negotiate/3 refuses raw activation taps against summary-only replay traces" do
    trace = activation_trace()

    plan =
      CrucibleTap.activation_tap("q0-raw", "blocks.0.attn.hook_q",
        capture_mode: :raw,
        bounds: [raw_allowed?: true]
      )

    assert {:error, {:tap_compile_failed, report}} = Replay.negotiate(trace, plan)
    assert [%Crucible.FailedCapability{reason: :unsupported_capture_mode}] = report.failed
  end

  test "negotiate/3 accepts raw activation taps when replay trace has a raw tensor ref" do
    trace = activation_trace(raw?: true)

    plan =
      CrucibleTap.activation_tap("q0-raw", "blocks.0.attn.hook_q",
        capture_mode: :raw,
        bounds: [raw_allowed?: true]
      )

    assert {:ok, compiled, report} = Replay.negotiate(trace, plan)
    assert compiled.report.matched != []
    assert report.failed == []
  end

  test "negotiate/3 degrades optional absent taps" do
    trace = Replay.load!(@fixture)

    plan =
      TapPlan.new!(
        [
          [id: "final-logits", kind: :read, required?: true, signal_type: :final_logits],
          [id: "hidden", kind: :read, required?: false, signal_type: :hidden_state]
        ],
        plan_id: "replay-plan-optional"
      )

    assert {:ok, _compiled, report} = Replay.negotiate(trace, plan)
    assert report.optional_dropped != [] or report.unsupported != []
  end

  test "load_directory/1 loads checked-in fixtures" do
    fixtures_dir = Path.expand("fixtures", __DIR__)

    assert {:ok, traces} = Replay.load_directory(fixtures_dir)
    assert length(traces) >= 1
    assert Enum.all?(traces, &match?(%Crucible.ForwardTrace{}, &1))
  end

  defp activation_trace(opts \\ []) do
    raw? = Keyword.get(opts, :raw?, false)

    signal_attrs = [
      signal_id: "q0",
      trace_id: "trace-activation-replay",
      signal_type: :attention_q,
      model_id: "model:fixture",
      tensor_summary: Crucible.TensorSummary.compute([1.0, 2.0, 3.0]),
      metadata: %{
        activation_name: "blocks.0.attn.hook_q",
        axes: [:batch, :pos, :head, :d_head]
      }
    ]

    signal_attrs =
      if raw? do
        Keyword.put(
          signal_attrs,
          :tensor_ref,
          %Crucible.TensorRef{
            uri: "file:///tmp/q0.f32",
            digest: "sha256:fixture",
            shape: [1, 1, 1, 3],
            dtype: :f32,
            byte_size: 12,
            format: :raw_f32
          }
        )
      else
        signal_attrs
      end

    Crucible.ForwardTrace.new!(
      trace_id: "trace-activation-replay",
      provider_kind: :fixture,
      model_id: "model:fixture",
      model_family: :fixture_decoder,
      signals: [Crucible.SignalRecord.new!(signal_attrs)]
    )
  end
end
