# Redaction

Redaction bounds oversized text and prevents raw tensor leakage.

## What This Covers

Use bounded previews and digests for large payloads.

## Worked Example

```elixir
CrucibleSignalTrace.Redactor.bounded(String.duplicate("a", 100), limit: 8)
```

## Related Guides

- [Forward Trace](forward_trace.md)
- [AITrace Export](ai_trace_export.md)
