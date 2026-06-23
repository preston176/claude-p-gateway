defmodule ClaudePGateway.Settings do
  @moduledoc """
  Runtime-mutable configuration: gateway token and rate-limit knobs.

  Initial values come from application env (which `config/runtime.exs`
  populates from environment variables). The admin settings page can
  mutate them at runtime via `update/1`, and changes are persisted to
  the JSON file at `STATE_PATH` if that env var is set. Without
  `STATE_PATH`, settings are in-memory only and reset on restart.
  """

  use GenServer

  @defaults %{
    rate_limit_capacity: 60,
    rate_limit_refill_per_minute: 60
  }

  ## Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(key) when is_atom(key), do: GenServer.call(__MODULE__, {:get, key})
  def all, do: GenServer.call(__MODULE__, :all)

  @doc """
  Update one or more keys. Returns the new full settings map.
  """
  def update(attrs) when is_map(attrs), do: GenServer.call(__MODULE__, {:update, attrs})

  def state_path, do: GenServer.call(__MODULE__, :state_path)

  ## Server

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path) || System.get_env("STATE_PATH")

    overrides = Application.get_env(:claude_p_gateway, :settings_defaults, %{})

    settings =
      @defaults
      |> Map.merge(overrides)
      |> Map.put(:gateway_token, Application.fetch_env!(:claude_p_gateway, :gateway_token))
      |> Map.merge(load(path))

    {:ok, %{settings: settings, path: path}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state.settings, key), state}
  end

  def handle_call(:all, _from, state) do
    {:reply, state.settings, state}
  end

  def handle_call(:state_path, _from, state) do
    {:reply, state.path, state}
  end

  def handle_call({:update, attrs}, _from, state) do
    sanitized = sanitize(attrs)
    new_settings = Map.merge(state.settings, sanitized)
    persist(state.path, new_settings)

    if Map.has_key?(sanitized, :rate_limit_capacity) or
         Map.has_key?(sanitized, :rate_limit_refill_per_minute) do
      ClaudePGateway.RateLimiter.refresh_config()
    end

    {:reply, new_settings, %{state | settings: new_settings}}
  end

  ## Internals

  defp sanitize(attrs) do
    attrs
    |> Enum.reduce(%{}, fn
      {:gateway_token, v}, acc when is_binary(v) and byte_size(v) >= 8 ->
        Map.put(acc, :gateway_token, v)

      {:rate_limit_capacity, v}, acc when is_integer(v) and v > 0 ->
        Map.put(acc, :rate_limit_capacity, v)

      {:rate_limit_refill_per_minute, v}, acc when is_integer(v) and v > 0 ->
        Map.put(acc, :rate_limit_refill_per_minute, v)

      _, acc ->
        acc
    end)
  end

  defp load(nil), do: %{}

  defp load(path) do
    with {:ok, body} <- File.read(path),
         {:ok, raw} <- Jason.decode(body) do
      raw
      |> Enum.into(%{}, fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> sanitize()
    else
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp persist(nil, _settings), do: :ok

  defp persist(path, settings) do
    encoded = Jason.encode!(settings, pretty: true)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, encoded)
  end
end
