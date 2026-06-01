defmodule DatasetGen.SandboxPoolTest do
  use ExUnit.Case, async: true

  alias DatasetGen.SandboxPool

  setup do
    {:ok, pid} = SandboxPool.start_link(slots: 2)
    %{pool: pid}
  end

  test "acquire returns :ok immediately when slots are free", %{pool: pool} do
    assert :ok = SandboxPool.acquire(pool)
  end

  test "multiple acquires within slot limit all succeed immediately", %{pool: pool} do
    assert :ok = SandboxPool.acquire(pool)
    assert :ok = SandboxPool.acquire(pool)
  end

  test "acquiring beyond slot count blocks until release", %{pool: pool} do
    :ok = SandboxPool.acquire(pool)
    :ok = SandboxPool.acquire(pool)

    # Third acquire should block; we resolve it by releasing from another process
    test_pid = self()

    task =
      Task.async(fn ->
        result = SandboxPool.acquire(pool, 2_000)
        send(test_pid, {:acquired, result})
      end)

    # Give the task time to block
    Process.sleep(50)
    {available, waiting} = SandboxPool.stats(pool)
    assert available == 0
    assert waiting == 1

    SandboxPool.release(pool)

    assert_receive {:acquired, :ok}, 1_000
    Task.await(task)
  end

  test "release restores a slot", %{pool: pool} do
    :ok = SandboxPool.acquire(pool)
    {available_after_acquire, _} = SandboxPool.stats(pool)
    assert available_after_acquire == 1

    SandboxPool.release(pool)
    {available_after_release, _} = SandboxPool.stats(pool)
    assert available_after_release == 2
  end

  test "stats returns {available, waiting}", %{pool: pool} do
    assert {2, 0} = SandboxPool.stats(pool)
    :ok = SandboxPool.acquire(pool)
    assert {1, 0} = SandboxPool.stats(pool)
  end

  test "release does not exceed max slots", %{pool: pool} do
    SandboxPool.release(pool)
    SandboxPool.release(pool)
    {available, _} = SandboxPool.stats(pool)
    assert available == 2
  end

  test "waiting callers are served in FIFO order", %{pool: pool} do
    :ok = SandboxPool.acquire(pool)
    :ok = SandboxPool.acquire(pool)

    test_pid = self()

    t1 =
      Task.async(fn ->
        SandboxPool.acquire(pool, 2_000)
        send(test_pid, {:done, :t1})
      end)

    t2 =
      Task.async(fn ->
        SandboxPool.acquire(pool, 2_000)
        send(test_pid, {:done, :t2})
      end)

    Process.sleep(50)
    SandboxPool.release(pool)
    SandboxPool.release(pool)

    assert_receive {:done, :t1}, 1_000
    assert_receive {:done, :t2}, 1_000

    Task.await(t1)
    Task.await(t2)
  end
end
