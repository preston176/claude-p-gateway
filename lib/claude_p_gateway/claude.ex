defmodule ClaudePGateway.Claude do
  @moduledoc """
  Thin wrapper around the locally-installed `claude` CLI.

  Each call shells out to `claude -p --output-format json` and returns the
  parsed response. We run the subprocess under `Task.Supervisor` so a stuck
  or crashing `claude` invocation cannot take the gateway down with it.
  """

  require Logger

  @type result :: %{text: String.t(), raw: map()}

  @default_timeout_ms 5 * 60 * 1000

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

  defp maybe_add_model(args, nil), do: args
  defp maybe_add_model(args, model) when is_binary(model), do: args ++ ["--model", model]

  defp claude_bin do
    Application.get_env(:claude_p_gateway, :claude_bin, "claude")
  end
end
