defmodule ClaudePGateway.ClaudeBehaviour do
  @moduledoc """
  Behaviour for the `claude -p` wrapper, so the implementation can be
  swapped under test (see `ClaudePGateway.MockClaude`).
  """

  @type result :: %{text: String.t(), raw: map()}

  @callback run(prompt :: String.t(), opts :: keyword()) ::
              {:ok, result()} | {:error, term()}

  @callback stream_into(conn :: Plug.Conn.t(), prompt :: String.t(), opts :: keyword()) ::
              Plug.Conn.t()
end
