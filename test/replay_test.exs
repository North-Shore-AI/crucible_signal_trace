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
end
