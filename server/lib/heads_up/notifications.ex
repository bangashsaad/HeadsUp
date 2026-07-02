defmodule HeadsUp.Notifications do
  @moduledoc """
  Push notifications via Expo's push service. `notify_user/4` looks up the
  user's stored device token and fires the send in the background — callers
  never block or fail because of a push (a notification is best-effort by
  nature). No-ops when the user has no token or pushes are disabled (test).

  Config:

      config :heads_up, HeadsUp.Notifications,
        enabled: true,
        push_url: "https://exp.host/--/api/v2/push/send",
        req_options: []   # tests inject a Req.Test plug here
  """
  require Logger

  import Ecto.Query, only: [from: 2]

  alias HeadsUp.Repo
  alias HeadsUp.Accounts.User

  @default_push_url "https://exp.host/--/api/v2/push/send"

  @doc """
  Send a push to a user (by id or struct). `data` rides along for tap-routing
  on the client (e.g. `%{type: "duel", duel_id: 42}`). Fire-and-forget.
  """
  def notify_user(user_or_id, title, body, data \\ %{})

  def notify_user(%User{push_token: token}, title, body, data), do: notify_token(token, title, body, data)

  def notify_user(user_id, title, body, data) when is_integer(user_id) do
    if enabled?() do
      in_background(fn ->
        token = Repo.one(from u in User, where: u.id == ^user_id, select: u.push_token)
        deliver(token, title, body, data)
      end)
    end

    :ok
  end

  @doc "Send a push straight to a device token (nil token no-ops). Fire-and-forget."
  def notify_token(token, title, body, data \\ %{}) do
    if enabled?(), do: in_background(fn -> deliver(token, title, body, data) end)
    :ok
  end

  @doc false
  # Synchronous delivery — exposed for tests; production goes through the
  # background wrappers above.
  def deliver(nil, _title, _body, _data), do: :skip

  def deliver(token, title, body, data) when is_binary(token) do
    payload = %{to: token, title: title, body: body, data: data, sound: "default"}
    opts = config(:req_options, [])

    request =
      Req.new(
        Keyword.merge(
          [url: config(:push_url, @default_push_url), json: payload, receive_timeout: 8_000, retry: false],
          opts
        )
      )

    case Req.post(request) do
      {:ok, %Req.Response{status: status}} when status < 400 ->
        :ok

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.warning("push send failed (#{status}): #{inspect(body)}")
        :error

      {:error, reason} ->
        Logger.warning("push send failed: #{inspect(reason)}")
        :error
    end
  end

  # --- helpers --------------------------------------------------------------

  defp in_background(fun) do
    Task.Supervisor.start_child(HeadsUp.Notifications.TaskSupervisor, fun)
  end

  defp enabled?, do: config(:enabled, false)

  defp config(key, default) do
    Application.get_env(:heads_up, __MODULE__, []) |> Keyword.get(key, default)
  end
end
