defmodule CrucibleSignalTrace.SecretScanTest do
  use ExUnit.Case, async: true

  alias CrucibleSignalTrace.SecretScan

  test "finds forbidden terms in nested map keys without leaking values" do
    payload = %{
      "provider" => %{
        "headers" => %{"authorization" => "Bearer live-secret"},
        "safe" => "ok"
      }
    }

    report = SecretScan.scan(payload)

    refute report.ok?
    assert Enum.any?(report.findings, &(&1.term == "headers"))
    assert Enum.any?(report.findings, &(&1.term == "authorization"))
    refute inspect(report.findings) =~ "live-secret"
  end

  test "finds forbidden terms in nested list values" do
    payload = %{"events" => [%{"message" => "contains bearer token marker"}]}

    report = SecretScan.scan(payload)

    refute report.ok?
    assert [%{term: "bearer"}] = report.findings
  end

  test "is case insensitive and fixed-string based" do
    payload = %{"Endpoint_Auth" => "present"}

    report = SecretScan.scan(payload)

    refute report.ok?
    assert [%{term: "endpoint_auth"}] = report.findings
  end

  test "supports caller supplied forbidden terms" do
    payload = %{"custom_secret" => "present"}

    report = SecretScan.scan(payload, forbidden_terms: ["custom_secret"])

    refute report.ok?
    assert [%{term: "custom_secret"}] = report.findings
  end

  test "bounds findings" do
    payload = %{"api_key" => "a", "authorization" => "b", "headers" => "c"}

    report = SecretScan.scan(payload, max_findings: 2)

    assert length(report.findings) == 2
    refute report.ok?
  end
end
