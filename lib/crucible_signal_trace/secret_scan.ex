defmodule CrucibleSignalTrace.SecretScan do
  @moduledoc """
  Fixed-string secret-field scanner for decoded trace/dataset records.

  Findings report only the path and matched forbidden term. Matched values are
  intentionally omitted so the scanner can be used in logs and operator reports.
  """

  @default_forbidden_terms [
    "api_key",
    "authorization",
    "bearer",
    "headers",
    "credential",
    "endpoint_auth",
    "raw_request_body",
    "raw_response_body"
  ]

  @spec default_forbidden_terms() :: [String.t()]
  def default_forbidden_terms, do: @default_forbidden_terms

  @spec scan(term(), keyword()) :: map()
  def scan(value, opts \\ []) when is_list(opts) do
    forbidden_terms =
      normalize_terms(Keyword.get(opts, :forbidden_terms, @default_forbidden_terms))

    max_findings = Keyword.get(opts, :max_findings, 50)
    findings = value |> scan_value(["root"], forbidden_terms, []) |> Enum.reverse()
    findings = Enum.take(findings, max(max_findings, 0))

    %{
      ok?: findings == [],
      forbidden_terms: forbidden_terms,
      findings: findings
    }
  end

  defp scan_value(_value, _path, _terms, findings) when length(findings) >= 50, do: findings

  defp scan_value(value, path, terms, findings) when is_map(value) do
    value
    |> Enum.sort_by(fn {key, _nested} -> to_string(key) end)
    |> Enum.reduce(findings, fn {key, nested}, acc ->
      key_text = to_string(key)
      key_path = path ++ [key_text]

      acc
      |> scan_text(key_text, key_path, "key", terms)
      |> then(&scan_value(nested, key_path, terms, &1))
    end)
  end

  defp scan_value(value, path, terms, findings) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.reduce(findings, fn {nested, index}, acc ->
      scan_value(nested, path ++ [Integer.to_string(index)], terms, acc)
    end)
  end

  defp scan_value(value, path, terms, findings) when is_binary(value),
    do: scan_text(findings, value, path, "value", terms)

  defp scan_value(_value, _path, _terms, findings), do: findings

  defp scan_text(findings, text, path, location, terms) do
    downcased = String.downcase(text)

    Enum.reduce(terms, findings, fn term, acc ->
      if String.contains?(downcased, term) do
        [%{path: path, location: location, term: term} | acc]
      else
        acc
      end
    end)
  end

  defp normalize_terms(terms) when is_list(terms) do
    terms
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_terms(_terms), do: @default_forbidden_terms
end
