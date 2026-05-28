trace =
  Crucible.ForwardTrace.new!(
    trace_id: "trace-aitrace-example",
    model_id: "model:fixture",
    input_hash: CrucibleSignalTrace.Digest.text("example")
  )

{:ok, evidence} = CrucibleSignalTrace.Export.AITrace.to_evidence(trace)

IO.puts(Jason.encode!(%{
  ok: true,
  example: "aitrace_export_live",
  schema: evidence.schema,
  version: evidence.version
}))
