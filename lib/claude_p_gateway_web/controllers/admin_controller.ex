defmodule ClaudePGatewayWeb.AdminController do
  use ClaudePGatewayWeb, :controller

  alias ClaudePGateway.{RateLimiter, Settings}

  def show(conn, params) do
    flash = Map.get(params, "msg")
    render_settings(conn, flash, nil)
  end

  def update(conn, params) do
    attrs = parse_attrs(params)

    case attrs do
      {:ok, attrs} ->
        _ = Settings.update(attrs)

        flash =
          cond do
            Map.has_key?(attrs, :gateway_token) and map_size(attrs) > 1 ->
              "settings updated; gateway token rotated"

            Map.has_key?(attrs, :gateway_token) ->
              "gateway token rotated"

            true ->
              "rate limits updated"
          end

        redirect(conn, to: ~p"/admin/settings?msg=#{flash}")

      {:error, reason} ->
        render_settings(conn, nil, reason)
    end
  end

  def rotate_token(conn, _params) do
    new_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    Settings.update(%{gateway_token: new_token})
    redirect(conn, to: ~p"/admin/settings?msg=#{"new token generated"}")
  end

  ## Internals

  defp parse_attrs(params) do
    attrs = %{}

    with {:ok, attrs} <- maybe_put_token(attrs, params),
         {:ok, attrs} <- maybe_put_int(attrs, params, "rate_limit_capacity", :rate_limit_capacity),
         {:ok, attrs} <-
           maybe_put_int(
             attrs,
             params,
             "rate_limit_refill_per_minute",
             :rate_limit_refill_per_minute
           ) do
      if map_size(attrs) == 0 do
        {:error, "no changes submitted"}
      else
        {:ok, attrs}
      end
    end
  end

  defp maybe_put_token(attrs, %{"gateway_token" => v}) when is_binary(v) do
    trimmed = String.trim(v)

    cond do
      trimmed == "" -> {:ok, attrs}
      byte_size(trimmed) < 16 -> {:error, "gateway token must be at least 16 characters"}
      true -> {:ok, Map.put(attrs, :gateway_token, trimmed)}
    end
  end

  defp maybe_put_token(attrs, _), do: {:ok, attrs}

  defp maybe_put_int(attrs, params, src, dst) do
    case Map.get(params, src) do
      nil ->
        {:ok, attrs}

      "" ->
        {:ok, attrs}

      v when is_binary(v) ->
        case Integer.parse(v) do
          {int, ""} when int > 0 -> {:ok, Map.put(attrs, dst, int)}
          _ -> {:error, "#{src} must be a positive integer"}
        end
    end
  end

  defp render_settings(conn, flash, error) do
    settings = Settings.all()
    status = RateLimiter.status()
    state_path = Settings.state_path()

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, page(settings, status, state_path, flash, error))
  end

  defp page(settings, status, state_path, flash, error) do
    persistence =
      case state_path do
        nil -> "in-memory only (changes reset on restart; set STATE_PATH to persist)"
        path -> "persisted to #{Plug.HTML.html_escape(path)}"
      end

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8" />
      <title>claude-p-gateway / admin / settings</title>
      <style>
        body { font: 14px/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace; max-width: 720px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; background: #fafafa; }
        h1 { font-size: 1.1rem; font-weight: 600; margin: 0 0 1.5rem; }
        h2 { font-size: 0.95rem; font-weight: 600; margin: 2rem 0 0.75rem; color: #444; }
        form { background: #fff; border: 1px solid #e3e3e3; border-radius: 6px; padding: 1.25rem; margin-bottom: 1rem; }
        label { display: block; margin: 0.75rem 0 0.25rem; color: #444; font-size: 0.85rem; }
        input[type=text], input[type=number] { width: 100%; padding: 0.5rem 0.6rem; border: 1px solid #ccc; border-radius: 4px; font: inherit; box-sizing: border-box; }
        input[type=submit], button { padding: 0.5rem 1rem; border: 1px solid #1a1a1a; background: #1a1a1a; color: #fff; border-radius: 4px; font: inherit; cursor: pointer; margin-top: 0.75rem; }
        button.secondary { background: #fff; color: #1a1a1a; }
        .row { display: flex; gap: 1rem; }
        .row > * { flex: 1; }
        .flash { background: #e8f5e9; border: 1px solid #c8e6c9; padding: 0.6rem 0.85rem; border-radius: 4px; margin-bottom: 1rem; color: #1b5e20; }
        .err { background: #ffebee; border: 1px solid #ffcdd2; padding: 0.6rem 0.85rem; border-radius: 4px; margin-bottom: 1rem; color: #b71c1c; }
        .muted { color: #777; font-size: 0.8rem; }
        code, pre { font: inherit; background: #f0f0f0; padding: 0.1rem 0.3rem; border-radius: 3px; }
        a { color: #1a1a1a; }
      </style>
    </head>
    <body>
      <h1>claude-p-gateway / settings</h1>
      #{flash_html(flash, error)}

      <h2>Rate limit</h2>
      <form method="post" action="/admin/settings">
        <input type="hidden" name="_csrf_token" value="#{csrf_token()}" />
        <div class="row">
          <div>
            <label for="rate_limit_capacity">Capacity (max bucket size)</label>
            <input type="number" id="rate_limit_capacity" name="rate_limit_capacity" min="1" value="#{settings.rate_limit_capacity}" />
          </div>
          <div>
            <label for="rate_limit_refill_per_minute">Refill per minute</label>
            <input type="number" id="rate_limit_refill_per_minute" name="rate_limit_refill_per_minute" min="1" value="#{settings.rate_limit_refill_per_minute}" />
          </div>
        </div>
        <p class="muted">Currently #{status.tokens_available} tokens available (of #{status.capacity}).</p>
        <input type="submit" value="Save rate limits" />
      </form>

      <h2>Gateway token</h2>
      <form method="post" action="/admin/settings">
        <input type="hidden" name="_csrf_token" value="#{csrf_token()}" />
        <label for="gateway_token">Current token</label>
        <input type="text" id="gateway_token" name="gateway_token" value="#{Plug.HTML.html_escape(settings.gateway_token)}" />
        <p class="muted">Edit to set a custom value (minimum 16 characters), or use the button below to generate a random 32-byte token.</p>
        <input type="submit" value="Save token" />
      </form>

      <form method="post" action="/admin/settings/rotate_token">
        <input type="hidden" name="_csrf_token" value="#{csrf_token()}" />
        <button class="secondary" type="submit">Generate new random token</button>
      </form>

      <h2>Persistence</h2>
      <p class="muted">#{persistence}</p>

      <p class="muted"><a href="/admin/dashboard">LiveDashboard &rarr;</a></p>
    </body>
    </html>
    """
  end

  defp flash_html(nil, nil), do: ""
  defp flash_html(msg, nil) when is_binary(msg), do: ~s(<div class="flash">#{Plug.HTML.html_escape(msg)}</div>)
  defp flash_html(_, err) when is_binary(err), do: ~s(<div class="err">#{Plug.HTML.html_escape(err)}</div>)

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()
end
