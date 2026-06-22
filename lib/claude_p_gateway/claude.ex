defmodule ClaudePGateway.Claude do
  @moduledoc """
  Thin wrapper around the locally-installed `claude` CLI.

  Two entry points:

    * `run/2`           - one-shot, parsed JSON response.
    * `stream_into/3`   - NDJSON streaming via `--output-format stream-json`,
                          piping each event into the caller's `Plug.Conn`
                          as a server-sent event.

  Each invocation is supervised so a stuck or crashing `claude` cannot take
  the gateway down with it.
  """

  require Logger

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
  `Plug.Conn`. The conn must already have been put into chunked mode with
  `send_chunked/2`. Returns the (possibly updated) conn.
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
        write_sse(conn, "error", %{type: "spawn_failed", message: "claude binary not found"})

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

        stream_loop(conn, port, timeout, "")
    end
  end

  defp stream_loop(conn, port, timeout, buffer) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        full = buffer <> line
        conn = forward_event(conn, full)
        stream_loop(conn, port, timeout, "")

      {^port, {:data, {:noeol, chunk}}} ->
        stream_loop(conn, port, timeout, buffer <> chunk)

      {^port, {:exit_status, 0}} ->
        write_sse(conn, "done", %{ok: true})

      {^port, {:exit_status, code}} ->
        write_sse(conn, "error", %{type: "claude_exit", code: code})
    after
      timeout ->
        _ = Port.info(port) && Port.close(port)
        write_sse(conn, "error", %{type: "timeout"})
    end
  end

  defp forward_event(conn, line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        conn

      String.starts_with?(trimmed, "{") ->
        case Jason.decode(trimmed) do
          {:ok, event} -> write_sse(conn, Map.get(event, "type", "message"), event)
          {:error, _} -> conn
        end

      true ->
        conn
    end
  end

  defp write_sse(conn, event, payload) do
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
