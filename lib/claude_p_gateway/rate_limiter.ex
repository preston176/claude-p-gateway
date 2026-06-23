defmodule ClaudePGateway.RateLimiter do
  @moduledoc """
  Single global token bucket. Each `check/0` consumes one token; if the
  bucket is empty the caller is told how many ms until the next token
  refills.

  Capacity and refill rate are read from `ClaudePGateway.Settings` at
  startup and again any time `refresh_config/0` is invoked (which the
  Settings store does whenever the admin page changes the values).
  """

  use GenServer

  alias ClaudePGateway.Settings

  ## Client

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec check() :: :ok | {:error, :rate_limited, non_neg_integer()}
  def check, do: GenServer.call(__MODULE__, :check)

  def refresh_config, do: GenServer.cast(__MODULE__, :refresh_config)

  @doc false
  def reset, do: GenServer.cast(__MODULE__, :reset)

  def status, do: GenServer.call(__MODULE__, :status)

  ## Server

  @impl true
  def init(_), do: {:ok, build_state()}

  @impl true
  def handle_call(:check, _from, state) do
    state = refill(state)

    if state.tokens >= 1.0 do
      {:reply, :ok, %{state | tokens: state.tokens - 1.0}}
    else
      retry_after_ms = max(1, round((1.0 - state.tokens) / max(state.refill_per_ms, 1.0e-9)))
      {:reply, {:error, :rate_limited, retry_after_ms}, state}
    end
  end

  def handle_call(:status, _from, state) do
    state = refill(state)

    {:reply,
     %{
       capacity: state.capacity,
       refill_per_minute: state.refill_per_minute,
       tokens_available: Float.round(state.tokens, 2)
     }, state}
  end

  @impl true
  def handle_cast(:refresh_config, state) do
    new_state = build_state()
    carried = min(new_state.capacity * 1.0, state.tokens)
    {:noreply, %{new_state | tokens: carried}}
  end

  def handle_cast(:reset, _state), do: {:noreply, build_state()}

  ## Internals

  defp build_state do
    capacity = Settings.get(:rate_limit_capacity)
    refill_per_minute = Settings.get(:rate_limit_refill_per_minute)

    %{
      capacity: capacity,
      refill_per_minute: refill_per_minute,
      refill_per_ms: refill_per_minute / 60_000,
      tokens: capacity * 1.0,
      last: now_ms()
    }
  end

  defp refill(state) do
    now = now_ms()
    elapsed = max(0, now - state.last)
    tokens = min(state.capacity * 1.0, state.tokens + elapsed * state.refill_per_ms)
    %{state | tokens: tokens, last: now}
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
