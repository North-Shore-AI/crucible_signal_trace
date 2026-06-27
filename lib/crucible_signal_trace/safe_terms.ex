defmodule CrucibleSignalTrace.SafeTerms do
  @moduledoc false

  @key_map %{
    "allow_tiny_fixture?" => :allow_tiny_fixture?,
    "activation_name" => :activation_name,
    "axes" => :axes,
    "backend" => :backend,
    "cache_summary" => :cache_summary,
    "capability_report" => :capability_report,
    "capability_report_digest" => :capability_report_digest,
    "capability_reason" => :capability_reason,
    "capability_status" => :capability_status,
    "capture_method" => :capture_method,
    "capture_mode" => :capture_mode,
    "completed_at" => :completed_at,
    "component" => :component,
    "decoding_steps" => :decoding_steps,
    "device" => :device,
    "digest" => :digest,
    "dtype" => :dtype,
    "duration_ms" => :duration_ms,
    "ended_at" => :ended_at,
    "entropy" => :entropy,
    "event_count" => :event_count,
    "event_id" => :event_id,
    "event_type" => :event_type,
    "events" => :events,
    "final_logits" => :final_logits,
    "fragment_id" => :fragment_id,
    "generated_token_id" => :generated_token_id,
    "generated_token_text" => :generated_token_text,
    "head_index" => :head_index,
    "input_hash" => :input_hash,
    "intervention_allowed?" => :intervention_allowed?,
    "kv_head_index" => :kv_head_index,
    "layer" => :layer,
    "layer_index" => :layer_index,
    "layer_trajectory" => :layer_trajectory,
    "logits_ref" => :logits_ref,
    "margin" => :margin,
    "max" => :max,
    "mean" => :mean,
    "metadata" => :metadata,
    "min" => :min,
    "model_family" => :model_family,
    "model_id" => :model_id,
    "model_ref" => :model_ref,
    "model_revision" => :model_revision,
    "nan_count" => :nan_count,
    "negative_infinity_count" => :negative_infinity_count,
    "node_name" => :node_name,
    "norm_l2" => :norm_l2,
    "occurred_at" => :occurred_at,
    "ordinal" => :ordinal,
    "payload" => :payload,
    "policy_decision_refs" => :policy_decision_refs,
    "positive_infinity_count" => :positive_infinity_count,
    "prompt_digest" => :prompt_digest,
    "provider_kind" => :provider_kind,
    "rank" => :rank,
    "raw_ref" => :raw_ref,
    "record" => :record,
    "requires_raw?" => :requires_raw?,
    "run_id" => :run_id,
    "schema_version" => :schema_version,
    "shape" => :shape,
    "signal" => :signal,
    "signal_id" => :signal_id,
    "signal_type" => :signal_type,
    "signals" => :signals,
    "source" => :source,
    "started_at" => :started_at,
    "status" => :status,
    "stddev" => :stddev,
    "steering" => :steering,
    "summary" => :summary,
    "surface_id" => :surface_id,
    "tap_id" => :tap_id,
    "tap_plan_digest" => :tap_plan_digest,
    "tap_plan_ref" => :tap_plan_ref,
    "tensor" => :tensor,
    "tensor_ref" => :tensor_ref,
    "tensor_summary" => :tensor_summary,
    "timestamp" => :timestamp,
    "token_id" => :token_id,
    "token_index" => :token_index,
    "token_text" => :token_text,
    "top_k" => :top_k,
    "trace_digest" => :trace_digest,
    "trace_id" => :trace_id,
    "trace_ref" => :trace_ref,
    "raw_values" => :raw_values
  }

  def normalize_keys(value) when is_map(value) do
    Map.new(value, fn
      {key, value} when is_binary(key) -> {Map.get(@key_map, key, key), normalize_nested(value)}
      {key, value} -> {key, normalize_nested(value)}
    end)
  end

  def normalize_keys(value), do: value

  def normalize_nested(value) when is_struct(value), do: value

  def normalize_nested(value) when is_map(value), do: normalize_keys(value)
  def normalize_nested(value) when is_list(value), do: Enum.map(value, &normalize_nested/1)
  def normalize_nested(value), do: value

  def atomize_existing(nil), do: nil
  def atomize_existing(value) when is_atom(value), do: value

  def atomize_existing(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  def atomize_existing(value), do: value

  def event_type(value) when is_atom(value), do: Atom.to_string(value)
  def event_type(value) when is_binary(value), do: value
  def event_type(value), do: value
end
