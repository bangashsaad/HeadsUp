defmodule HeadsUpWeb.MobileGate do
  @moduledoc """
  Phones don't get the desktop web app — they get the gate page pointing at
  the iOS app (Saad's call: the app IS the mobile experience; a phone-sized
  website would be a third parity surface forever).

  Gates PHONE user agents only: iPhone/iPod, Android phones (Android UAs
  carry "Mobile" on phones and not on tablets). iPads and computers pass
  untouched. The gate page's escape hatch sets a SESSION cookie that turns
  this plug off until the browser closes — the web version stays reachable,
  never by accident, and never for long: the first version remembered the
  choice for 180 days, so one curious tap hid the gate for half a year.

  Safari's "Request Desktop Website" reports a Mac user-agent and slips past
  this plug; `phone_gate_script/0` is the in-page backstop for that case.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  # v2: the old `mobile_web_ok` (180-day) cookie is deliberately ignored.
  @bypass_cookie "mobile_web_session"
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

  @doc """
  Inline backstop for phones whose user-agent lies (Safari "Request Desktop
  Website"): a touch device with a phone-sized screen on a gated path goes to
  the gate unless this session's escape cookie is set. Ungated paths (legal,
  the gate itself) are never touched.
  """
  def phone_gate_script do
    """
    (function(){try{var c=document.cookie.indexOf('#{@bypass_cookie}=1')>-1;var p=location.pathname;var g=p==='/'||/^\/(login|signup|app|forgot-password|reset-password)(\/|$)/.test(p);var phone=navigator.maxTouchPoints>1&&Math.min(screen.width,screen.height)<600;if(g&&phone&&!c){location.replace('/get-the-app')}}catch(e){}})();
    """
  end

  defp phone?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() || ""

    not Regex.match?(@bot_ua, ua) and
      (Regex.match?(@phone_ua, ua) or Regex.match?(@android_phone, ua))
  end
end
