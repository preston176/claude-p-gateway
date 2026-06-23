defmodule ClaudePGateway.AnthropicTranslator do
  @moduledoc """
  Translates the NDJSON event stream emitted by `claude -p
  --output-format stream-json --verbose` into the event vocabulary that
  Anthropic's `/v1/messages` streaming endpoint uses:

      message_start, content_block_start, content_block_delta,
      content_block_stop, message_delta, message_stop

  The translator carries state across calls (`new/0` returns a fresh
  one), so each call to `translate/2` returns `{events, new_state}`
  where `events` is a possibly-empty list of decoded Anthropic events
  ready to be encoded as SSE frames.

  Assumes claude's assistant events are cumulative (each one carries
  the full accumulated text so far). When they're not, the delta we
  emit is the full text, which is at worst noisy but still parseable.
  """

  defstruct started?: false,
            block_open?: false,
            block_index: 0,
            text_acc: "",
            model: "claude",
            message_id: nil,
            stop_reason: "end_turn",
            usage: %{input_tokens: 0, output_tokens: 0}

  @type t :: %__MODULE__{
          started?: boolean(),
          block_open?: boolean(),
          block_index: non_neg_integer(),
          text_acc: String.t(),
          model: String.t(),
          message_id: String.t() | nil,
          stop_reason: String.t(),
          usage: map()
        }

  def new, do: %__MODULE__{}

  @doc """
  Translate one raw event. Returns `{[anthropic_events], new_state}`.
  """
  @spec translate(t(), map()) :: {[map()], t()}
  def translate(state, %{"type" => "system", "subtype" => "init"} = ev) do
    model = Map.get(ev, "model", state.model)
    {start_events(%{state | model: model}), %{state | model: model, started?: true}}
  end

  def translate(state, %{"type" => "assistant", "message" => msg}) do
    state = ensure_started(state)
    text = extract_text(msg["content"])
    delta = compute_delta(state.text_acc, text)
    msg_id = msg["id"] || state.message_id
    model = msg["model"] || state.model
    usage = merge_usage(state.usage, msg["usage"])

    {open_events, state} = maybe_open_block(state)

    delta_events =
      if delta == "" do
        []
      else
        [
          %{
            type: "content_block_delta",
            index: state.block_index,
            delta: %{type: "text_delta", text: delta}
          }
        ]
      end

    new_state = %{
      state
      | text_acc: text,
        message_id: msg_id,
        model: model,
        usage: usage
    }

    {open_events ++ delta_events, new_state}
  end

  def translate(state, %{"type" => "result"} = ev) do
    state =
      state
      |> ensure_started()
      |> update_stop_reason(ev)
      |> Map.update!(:usage, &merge_usage(&1, ev["usage"]))

    close_events =
      cond do
        state.block_open? ->
          [%{type: "content_block_stop", index: state.block_index}]

        true ->
          []
      end

    finalisation = [
      %{
        type: "message_delta",
        delta: %{stop_reason: state.stop_reason, stop_sequence: nil},
        usage: state.usage
      },
      %{type: "message_stop"}
    ]

    {close_events ++ finalisation, %{state | block_open?: false}}
  end

  def translate(state, _other), do: {[], state}

  @doc """
  Encode a single translated event as an SSE frame string.
  """
  @spec encode_sse(map()) :: iodata()
  def encode_sse(%{type: type} = event) do
    ["event: ", to_string(type), "\ndata: ", Jason.encode_to_iodata!(event), "\n\n"]
  end

  ## Internals

  defp start_events(state) do
    [
      %{
        type: "message_start",
        message: %{
          id: state.message_id || gen_id(),
          type: "message",
          role: "assistant",
          model: state.model,
          content: [],
          stop_reason: nil,
          stop_sequence: nil,
          usage: state.usage
        }
      }
    ]
  end

  defp ensure_started(%{started?: true} = state), do: state

  defp ensure_started(state) do
    %{state | started?: true, message_id: state.message_id || gen_id()}
  end

  defp maybe_open_block(%{block_open?: true} = state), do: {[], state}

  defp maybe_open_block(state) do
    event = %{
      type: "content_block_start",
      index: state.block_index,
      content_block: %{type: "text", text: ""}
    }

    {[event], %{state | block_open?: true}}
  end

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.map(fn
      %{"type" => "text", "text" => t} -> t
      %{"text" => t} -> t
      _ -> ""
    end)
    |> Enum.join("")
  end

  defp extract_text(_), do: ""

  defp compute_delta(prev, full) do
    if String.starts_with?(full, prev) do
      binary_part(full, byte_size(prev), byte_size(full) - byte_size(prev))
    else
      full
    end
  end

  defp merge_usage(current, nil), do: current

  defp merge_usage(current, incoming) when is_map(incoming) do
    Map.merge(current, %{
      input_tokens: incoming["input_tokens"] || current.input_tokens,
      output_tokens: incoming["output_tokens"] || current.output_tokens
    })
  end

  defp update_stop_reason(state, %{"subtype" => "success"}), do: %{state | stop_reason: "end_turn"}
  defp update_stop_reason(state, %{"is_error" => true}), do: %{state | stop_reason: "error"}
  defp update_stop_reason(state, _), do: state

  defp gen_id, do: "msg_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
end
