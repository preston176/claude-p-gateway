defmodule ClaudePGateway.Claude do
  @moduledoc """
  Thin wrapper around the locally-installed `claude` CLI.

  Two entry points:

    * `run/2`           - one-shot, parsed JSON response.
    * `stream_into/3`   - NDJSON streaming via `--output-format stream-json`,
                          translated to Anthropic-shaped SSE events through
                          `ClaudePGateway.AnthropicTranslator` and written
                          straight onto the supplied `Plug.Conn`.

  Each invocation is supervised so a stuck or crashing `claude` cannot take
  the gateway down with it.
  """

  @behaviour ClaudePGateway.ClaudeBehaviour

  require Logger

  alias ClaudePGateway.AnthropicTranslator

  @type result :: %{text: String.t(), raw: map()}

  @default_timeout_ms 5 * 60 * 1000

  @doc """
  Run `claude -p` once and return the parsed JSON result.
  """
  @spec run(String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(prompt, opts \\ []) when is_binary(prompt) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    model = Keyword.get(opts, :model)

    task =
      Task.Supervisor.async_nolink(ClaudePGateway.TaskSupervisor, fn ->
        do_run(prompt, model)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, _} = ok} -> ok
      {:ok, {:error, _} = err} -> err
      {:exit, reason} -> {:error, {:claude_crashed, reason}}
      nil -> {:error, :timeout}
    end
  end

  defp do_run(prompt, model) do
    args =
      ["-p", prompt, "--output-format", "json"]
      |> maybe_add_model(model)

    case System.cmd(claude_bin(), args, stderr_to_stdout: false) do
      {stdout, 0} ->
        with {:ok, raw} <- Jason.decode(stdout) do
          {:ok, %{text: Map.get(raw, "result", stdout), raw: raw}}
        end

      {output, code} ->
        Logger.warning("claude exited #{code}: #{output}")
        {:error, {:claude_exit, code, output}}
    end
  rescue
    e in ErlangError -> {:error, {:spawn_failed, Exception.message(e)}}
  end

  @doc """
  Stream `claude -p --output-format stream-json --verbose` into the given
  `Plug.Conn` as Anthropic-shaped SSE events. The conn must already have
  been put into chunked mode with `send_chunked/2`.
  """
  @spec stream_into(Plug.Conn.t(), String.t(), keyword()) :: Plug.Conn.t()
  def stream_into(conn, prompt, opts \\ []) when is_binary(prompt) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)
    model = Keyword.get(opts, :model)

    args =
      ["-p", prompt, "--output-format", "stream-json", "--verbose"]
      |> maybe_add_model(model)

    case System.find_executable(claude_bin()) do
      nil ->
        write_raw_sse(conn, "error", %{type: "spawn_failed", message: "claude binary not found"})

      path ->
        port =
          Port.open({:spawn_executable, path}, [
            :binary,
            :exit_status,
            :hide,
            :stderr_to_stdout,
            {:args, args},
            {:line, 65_536}
          ])

        stream_loop(conn, port, timeout, "", AnthropicTranslator.new())
    end
  end

  defp stream_loop(conn, port, timeout, buffer, translator) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        full = buffer <> line
        {conn, translator} = forward_line(conn, translator, full)
        stream_loop(conn, port, timeout, "", translator)

      {^port, {:data, {:noeol, chunk}}} ->
        stream_loop(conn, port, timeout, buffer <> chunk, translator)

      {^port, {:exit_status, 0}} ->
        conn

      {^port, {:exit_status, code}} ->
        write_raw_sse(conn, "error", %{type: "claude_exit", code: code})
    after
      timeout ->
        _ = Port.info(port) && Port.close(port)
        write_raw_sse(conn, "error", %{type: "timeout"})
    end
  end

  defp forward_line(conn, translator, line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        {conn, translator}

      String.starts_with?(trimmed, "{") ->
        case Jason.decode(trimmed) do
          {:ok, event} ->
            {events, translator} = AnthropicTranslator.translate(translator, event)
            conn = Enum.reduce(events, conn, &write_translated_event(&2, &1))
            {conn, translator}

          {:error, _} ->
            {conn, translator}
        end

      true ->
        {conn, translator}
    end
  end

  defp write_translated_event(conn, event) do
    case Plug.Conn.chunk(conn, AnthropicTranslator.encode_sse(event)) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp write_raw_sse(conn, event, payload) do
    data = "event: #{event}\ndata: #{Jason.encode!(payload)}\n\n"

    case Plug.Conn.chunk(conn, data) do
      {:ok, conn} -> conn
      {:error, _} -> conn
    end
  end

  defp maybe_add_model(args, nil), do: args
  defp maybe_add_model(args, model) when is_binary(model), do: args ++ ["--model", model]

  defp claude_bin do
    Application.get_env(:claude_p_gateway, :claude_bin, "claude")
  end
end
