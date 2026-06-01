defmodule Reverie.ApplicationTest do
  use ExUnit.Case, async: true

  test "application supervisor is running" do
    assert Process.whereis(Reverie.Supervisor) != nil
  end
end
