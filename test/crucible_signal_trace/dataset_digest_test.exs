defmodule CrucibleSignalTrace.DatasetDigestTest do
  use ExUnit.Case, async: true

  alias CrucibleSignalTrace.DatasetDigest

  test "digests rows deterministically with canonical key ordering" do
    rows_a = [%{"b" => 2, "a" => %{"z" => 1, "x" => 0}}]
    rows_b = [%{"a" => %{"x" => 0, "z" => 1}, "b" => 2}]

    assert {:ok, report_a} = DatasetDigest.digest_rows(rows_a)
    assert {:ok, report_b} = DatasetDigest.digest_rows(rows_b)

    assert report_a.dataset_digest == report_b.dataset_digest
    assert report_a.row_count == 1
    assert report_a.row_order == "preserved"
  end

  test "digest is row-order sensitive" do
    assert {:ok, first} = DatasetDigest.digest_rows([%{"id" => 1}, %{"id" => 2}])
    assert {:ok, second} = DatasetDigest.digest_rows([%{"id" => 2}, %{"id" => 1}])

    refute first.dataset_digest == second.dataset_digest
  end

  test "reads JSONL into string-key maps without atomizing input keys" do
    path = tmp_path("dataset_digest_keys.jsonl")
    File.write!(path, ~s({"event":"one","nested":{"api_key":"redacted"}}\n))

    assert {:ok, [%{"event" => "one", "nested" => %{"api_key" => "redacted"}}]} =
             DatasetDigest.read_jsonl(path)
  end

  test "blank JSONL lines fail unless explicitly ignored" do
    path = tmp_path("dataset_digest_blank.jsonl")
    File.write!(path, ~s({"id":1}\n\n{"id":2}\n))

    assert {:error, {:blank_line, ^path, 2}} = DatasetDigest.read_jsonl(path)
    assert {:ok, report} = DatasetDigest.digest_jsonl(path, ignore_blank?: true)
    assert report.row_count == 2
  end

  test "invalid JSON fails with path and line" do
    path = tmp_path("dataset_digest_invalid.jsonl")
    File.write!(path, ~s({"id":1}\nnot-json\n))

    assert {:error, {:invalid_json, ^path, 2, _reason}} = DatasetDigest.read_jsonl(path)
  end

  defp tmp_path(name) do
    dir = Path.join(["tmp", "test", "crucible_signal_trace"])
    File.mkdir_p!(dir)
    Path.join(dir, name)
  end
end
