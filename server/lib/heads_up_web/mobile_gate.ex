defmodule HeadsUpWeb.MobileGate do
  @moduledoc """
  Phones don't get the web app — they get the gate page pointing at the iOS
  app, full stop (Saad's call: the app IS the mobile experience; a phone-sized
  website would be a third parity surface forever, and for now there is no
  escape hatch at all — an earlier one let a single curious tap hide the gate
  for months).

  Gates PHONE user agents only: iPhone/iPod, Android phones (Android UAs
  carry "Mobile" on phones and not on tablets). iPads and computers pass
  untouched. Safari's "Request Desktop Website" reports a Mac user-agent and
  slips past this plug; `phone_gate_script/0` is the in-page backstop.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @phone_ua ~r/iPhone|iPod|Windows Phone/
  @android_phone ~r/Android(?=.*Mobile)/
  # Crawlers and link-preview fetchers use phone user-agents (Google indexes
  # mobile-first; iMessage previews masquerade as facebookexternalhit). They
  # get the real site, or the landing page is what stops being indexed.
  @bot_ua ~r/bot|crawl|spider|slurp|facebookexternalhit|whatsapp|telegram|discord|slack|preview/i


  @behaviour Plug
  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts), do: gate_phones(conn, opts)

  def gate_phones(conn, _opts) do
    if phone?(conn), do: conn |> redirect(to: "/get-the-app") |> halt(), else: conn
  end

  @doc """
  Inline backstop for phones whose user-agent lies (Safari "Request Desktop
  Website"): a touch device with a phone-sized screen on a gated path goes to
  the gate. Ungated paths (legal, the gate itself) are never touched.
  """
  def phone_gate_script do
    """
    (function(){try{var p=location.pathname;var g=p==='/'||/^\/(login|signup|app|forgot-password|reset-password)(\/|$)/.test(p);var phone=navigator.maxTouchPoints>1&&Math.min(screen.width,screen.height)<600;if(g&&phone){location.replace('/get-the-app')}}catch(e){}})();
    """
  end

  defp phone?(conn) do
    ua = conn |> get_req_header("user-agent") |> List.first() || ""

    not Regex.match?(@bot_ua, ua) and
      (Regex.match?(@phone_ua, ua) or Regex.match?(@android_phone, ua))
  end
end
