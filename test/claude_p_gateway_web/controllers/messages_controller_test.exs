defmodule ClaudePGatewayWeb.MessagesControllerTest do
  # async: false because the 429 test mutates global RateLimiter / Settings.
  use ClaudePGatewayWeb.ConnCase, async: false

  import Mox

  setup :verify_on_exit!

  @token Application.compile_env!(:claude_p_gateway, :gateway_token)
  @auth {"authorization", "Bearer " <> @token}

  describe "POST /v1/messages (unauthenticated)" do
    test "returns 401 without bearer token", %{conn: conn} do
      conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
      assert json_response(conn, 401)["error"]["type"] == "unauthorized"
    end

    test "returns 401 with wrong token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer wrong")
        |> post(~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})

      assert json_response(conn, 401)["error"]["type"] == "unauthorized"
    end
  end

  describe "POST /v1/messages (authenticated)" do
    setup %{conn: conn} do
      {:ok, conn: put_req_header(conn, elem(@auth, 0), elem(@auth, 1))}
    end

    test "returns 400 when messages array is missing", %{conn: conn} do
      conn = post(conn, ~p"/v1/messages", %{})
      assert json_response(conn, 400)["error"]["type"] == "invalid_request"
    end

    test "returns 400 when messages is empty", %{conn: conn} do
      conn = post(conn, ~p"/v1/messages", %{messages: []})
      assert json_response(conn, 400)["error"]["type"] == "invalid_request"
    end

    test "returns Anthropic-shaped envelope on success", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn prompt, opts ->
        assert prompt =~ "Human: hi"
        assert opts[:model] == nil
        {:ok, %{text: "pong", raw: %{"result" => "pong"}}}
      end)

      conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
      body = json_response(conn, 200)

      assert body["type"] == "message"
      assert body["role"] == "assistant"
      assert body["stop_reason"] == "end_turn"
      assert [%{"type" => "text", "text" => "pong"}] = body["content"]
      assert String.starts_with?(body["id"], "msg_")
    end

    test "passes model through to claude", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn _prompt, opts ->
        assert opts[:model] == "claude-sonnet-4-6"
        {:ok, %{text: "ok", raw: %{}}}
      end)

      post(conn, ~p"/v1/messages", %{
        model: "claude-sonnet-4-6",
        messages: [%{role: "user", content: "hi"}]
      })
    end

    test "flattens content blocks before prompting", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn prompt, _opts ->
        assert prompt =~ "part one"
        assert prompt =~ "part two"
        {:ok, %{text: "ok", raw: %{}}}
      end)

      post(conn, ~p"/v1/messages", %{
        messages: [
          %{
            role: "user",
            content: [
              %{type: "text", text: "part one"},
              %{type: "text", text: "part two"}
            ]
          }
        ]
      })
    end

    test "prepends system prompt when provided", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn prompt, _opts ->
        assert String.starts_with?(prompt, "System: you are terse")
        {:ok, %{text: "ok", raw: %{}}}
      end)

      post(conn, ~p"/v1/messages", %{
        system: "you are terse",
        messages: [%{role: "user", content: "hi"}]
      })
    end

    test "504 on timeout from claude", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn _, _ -> {:error, :timeout} end)

      conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
      assert json_response(conn, 504)["error"]["type"] == "timeout"
    end

    test "502 on non-zero claude exit", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn _, _ ->
        {:error, {:claude_exit, 1, "boom"}}
      end)

      conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
      body = json_response(conn, 502)
      assert body["error"]["type"] == "claude_exit"
      assert body["error"]["message"] =~ "boom"
    end

    test "500 on unexpected error", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :run, fn _, _ -> {:error, :wat} end)

      conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
      assert json_response(conn, 500)["error"]["type"] == "internal_error"
    end

    test "returns 429 when rate limiter is empty", %{conn: conn} do
      original = ClaudePGateway.Settings.all()

      try do
        ClaudePGateway.Settings.update(%{rate_limit_capacity: 1, rate_limit_refill_per_minute: 1})
        Enum.each(1..2, fn _ -> ClaudePGateway.RateLimiter.check() end)

        conn = post(conn, ~p"/v1/messages", %{messages: [%{role: "user", content: "hi"}]})
        body = json_response(conn, 429)
        assert body["error"]["type"] == "rate_limited"
        assert is_integer(body["error"]["retry_after_ms"])
        assert get_resp_header(conn, "retry-after") != []
      after
        ClaudePGateway.Settings.update(%{
          rate_limit_capacity: original.rate_limit_capacity,
          rate_limit_refill_per_minute: original.rate_limit_refill_per_minute
        })

        ClaudePGateway.RateLimiter.reset()
      end
    end

    test "routes stream=true to stream_into/3", %{conn: conn} do
      expect(ClaudePGateway.MockClaude, :stream_into, fn conn, prompt, _opts ->
        assert prompt =~ "Human: hi"
        {:ok, conn} = Plug.Conn.chunk(conn, "event: done\ndata: {}\n\n")
        conn
      end)

      conn =
        post(conn, ~p"/v1/messages", %{
          stream: true,
          messages: [%{role: "user", content: "hi"}]
        })

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]
      assert conn.resp_body =~ "event: done"
    end
  end
end
