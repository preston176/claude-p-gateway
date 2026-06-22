defmodule ClaudePGatewayWeb.MessagesController do
  use ClaudePGatewayWeb, :controller

  alias ClaudePGateway.Claude

  def create(conn, %{"messages" => messages} = params) when is_list(messages) and messages != [] do
    prompt = build_prompt(messages, Map.get(params, "system"))
    model = Map.get(params, "model")

    case Claude.run(prompt, model: model) do
      {:ok, %{text: text, raw: raw}} ->
        json(conn, response_envelope(text, model, raw))

      {:error, :timeout} ->
        send_error(conn, 504, "timeout", "claude did not respond in time")

      {:error, {:claude_exit, code, output}} ->
        send_error(conn, 502, "claude_exit", "claude exited #{code}: #{truncate(output)}")

      {:error, reason} ->
        send_error(conn, 500, "internal_error", inspect(reason))
    end
  end

  def create(conn, _params) do
    send_error(conn, 400, "invalid_request", "messages required and must be a non-empty array")
  end

  defp build_prompt(messages, system) do
    sys_part = if is_binary(system) and system != "", do: ["System: " <> system], else: []

    msg_parts =
      Enum.map(messages, fn
        %{"role" => role, "content" => content} ->
          "#{role_label(role)}: #{flatten_content(content)}"

        _ ->
          ""
      end)
      |> Enum.reject(&(&1 == ""))

    Enum.join(sys_part ++ msg_parts, "\n\n")
  end

  defp role_label("user"), do: "Human"
  defp role_label("assistant"), do: "Assistant"
  defp role_label(other), do: String.capitalize(to_string(other))

  defp flatten_content(content) when is_binary(content), do: content

  defp flatten_content(blocks) when is_list(blocks) do
    blocks
    |> Enum.map(fn
      %{"type" => "text", "text" => text} -> text
      %{"text" => text} -> text
      _ -> ""
    end)
    |> Enum.join("\n")
  end

  defp flatten_content(_), do: ""

  defp response_envelope(text, model, raw) do
    %{
      id: "msg_" <> random_id(),
      type: "message",
      role: "assistant",
      model: model || "claude",
      content: [%{type: "text", text: text}],
      stop_reason: "end_turn",
      usage: %{input_tokens: 0, output_tokens: 0},
      _meta: %{source: "claude-p-gateway", raw: raw}
    }
  end

  defp random_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp send_error(conn, status, type, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{type: type, message: message}})
  end

  defp truncate(s) when is_binary(s) and byte_size(s) > 500, do: binary_part(s, 0, 500) <> "..."
  defp truncate(s), do: s
end
