defmodule CrucibleSignalTraceTest do
  use ExUnit.Case
  doctest CrucibleSignalTrace

  test "exposes package version" do
    assert CrucibleSignalTrace.version() == "0.1.0"
  end
end
