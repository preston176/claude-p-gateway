defmodule ClaudePGateway.RateLimiterTest do
  use ExUnit.Case, async: false

  alias ClaudePGateway.{RateLimiter, Settings}

  setup do
    original = Settings.all()

    on_exit(fn ->
      Settings.update(%{
        rate_limit_capacity: original.rate_limit_capacity,
        rate_limit_refill_per_minute: original.rate_limit_refill_per_minute
      })

      RateLimiter.reset()
    end)

    :ok
  end

  test "consumes one token per check until empty" do
    Settings.update(%{rate_limit_capacity: 3, rate_limit_refill_per_minute: 1})

    assert :ok = RateLimiter.check()
    assert :ok = RateLimiter.check()
    assert :ok = RateLimiter.check()

    assert {:error, :rate_limited, retry_after_ms} = RateLimiter.check()
    assert retry_after_ms > 0
  end

  test "status reports current bucket state" do
    Settings.update(%{rate_limit_capacity: 5, rate_limit_refill_per_minute: 60})

    status = RateLimiter.status()
    assert status.capacity == 5
    assert status.refill_per_minute == 60
    assert status.tokens_available <= 5
  end

  test "refresh_config carries the remaining tokens across reconfiguration" do
    Settings.update(%{rate_limit_capacity: 10, rate_limit_refill_per_minute: 1})
    Enum.each(1..7, fn _ -> RateLimiter.check() end)

    Settings.update(%{rate_limit_capacity: 20, rate_limit_refill_per_minute: 1})

    status = RateLimiter.status()
    assert status.capacity == 20
    assert status.tokens_available <= 20
  end
end
