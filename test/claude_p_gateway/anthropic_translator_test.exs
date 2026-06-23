defmodule ClaudePGateway.AnthropicTranslatorTest do
  use ExUnit.Case, async: true

  alias ClaudePGateway.AnthropicTranslator

  test "system init emits message_start" do
    {events, _state} =
      AnthropicTranslator.new()
      |> AnthropicTranslator.translate(%{
        "type" => "system",
        "subtype" => "init",
        "model" => "claude-sonnet-4-6"
      })

    assert [%{type: "message_start", message: msg}] = events
    assert msg.role == "assistant"
    assert msg.model == "claude-sonnet-4-6"
    assert msg.content == []
  end

  test "first assistant event opens content block and emits delta" do
    state = AnthropicTranslator.new()
    {_, state} = AnthropicTranslator.translate(state, %{"type" => "system", "subtype" => "init"})

    {events, state} =
      AnthropicTranslator.translate(state, %{
        "type" => "assistant",
        "message" => %{
          "id" => "msg_abc",
          "content" => [%{"type" => "text", "text" => "hi there"}]
        }
      })

    assert [
             %{type: "content_block_start", index: 0, content_block: %{type: "text"}},
             %{type: "content_block_delta", index: 0, delta: %{type: "text_delta", text: "hi there"}}
           ] = events

    assert state.block_open?
    assert state.text_acc == "hi there"
  end

  test "subsequent assistant events emit only the new suffix as a delta" do
    state =
      Enum.reduce(
        [
          %{"type" => "system", "subtype" => "init"},
          %{"type" => "assistant", "message" => %{"content" => [%{"type" => "text", "text" => "hello"}]}}
        ],
        AnthropicTranslator.new(),
        fn ev, acc ->
          {_, acc} = AnthropicTranslator.translate(acc, ev)
          acc
        end
      )

    {events, _state} =
      AnthropicTranslator.translate(state, %{
        "type" => "assistant",
        "message" => %{"content" => [%{"type" => "text", "text" => "hello world"}]}
      })

    refute Enum.any?(events, &(&1.type == "content_block_start"))
    assert [%{type: "content_block_delta", delta: %{text: " world"}}] = events
  end

  test "result event closes the block and finalises the message" do
    state =
      Enum.reduce(
        [
          %{"type" => "system", "subtype" => "init"},
          %{"type" => "assistant", "message" => %{"content" => [%{"type" => "text", "text" => "ok"}]}}
        ],
        AnthropicTranslator.new(),
        fn ev, acc ->
          {_, acc} = AnthropicTranslator.translate(acc, ev)
          acc
        end
      )

    {events, _state} =
      AnthropicTranslator.translate(state, %{
        "type" => "result",
        "subtype" => "success",
        "usage" => %{"input_tokens" => 4, "output_tokens" => 1}
      })

    types = Enum.map(events, & &1.type)
    assert types == ["content_block_stop", "message_delta", "message_stop"]

    message_delta = Enum.find(events, &(&1.type == "message_delta"))
    assert message_delta.delta.stop_reason == "end_turn"
    assert message_delta.usage.input_tokens == 4
  end

  test "encode_sse produces a valid SSE frame" do
    event = %{type: "ping", at: 1}
    frame = event |> AnthropicTranslator.encode_sse() |> IO.iodata_to_binary()

    assert frame =~ ~r/\Aevent: ping\ndata: .+\n\n\z/
    assert frame =~ "\"type\":\"ping\""
  end
end
