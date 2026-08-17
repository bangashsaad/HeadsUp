defmodule HeadsUpWeb.MobileGate do
  @moduledoc """
  Phones don't get the desktop web app — they get the gate page pointing at
  the iOS app (Saad's call: the app IS the mobile experience; a phone-sized
  website would be a third parity surface forever).

  Gates PHONE user agents only: iPhone/iPod, Android phones (Android UAs
  carry "Mobile" on phones and not on tablets). iPads and computers pass
  untouched. The gate page's escape hatch sets a long-lived cookie that
  turns this plug off for the device — the web version stays reachable,
  just never by accident.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @bypass_cookie "mobile_web_ok"
  @phone_ua ~r/iPhone|iPod|Windows Phone/
  @android_phone ~r/Android(?=.*Mobile)/
  # Crawlers and link-preview fetchers use phone user-agents (Google indexes
  # mobile-first; iMessage previews masquerade as facebookexternalhit). They
  # get the real site, or the landing page is what stops being indexed.
  @bot_ua ~r/bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|discord|slack|preview/i

  def bypass_cookie, do: @bypass_cookie

  @behaviour Plug
  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: gate_phones(conn, opts)

  def gate_phones(conn, _opts) do
    cond do
      conn.req_cookies[@bypass_cookie] == "1" -> conn
      not phone?(conn) -> conn
      true -> conn |> redirect(to: "/get-the-app") |> halt()
    end
  end

  defp phone?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() || ""

    not Regex.match?(@bot_ua, ua) and
      (Regex.match?(@phone_ua, ua) or Regex.match?(@android_phone, ua))
  end
end
