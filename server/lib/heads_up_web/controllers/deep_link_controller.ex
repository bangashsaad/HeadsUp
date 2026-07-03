defmodule HeadsUpWeb.DeepLinkController do
  @moduledoc """
  Universal-link plumbing. Apple fetches `/.well-known/apple-app-site-association`
  to learn which paths open the app; humans without the app who tap a shared
  link land on the fallback page instead. The path list lives HERE (server-side,
  changeable anytime) — only the `applinks:` domain entitlement is baked into
  the iOS build.
  """
  use HeadsUpWeb, :controller

  @team_id "VFX855N66M"
  @bundle_id "com.headsupfantasy.app"

  def aasa(conn, _params) do
    app_id = "#{@team_id}.#{@bundle_id}"

    json(conn, %{
      applinks: %{
        apps: [],
        details: [
          %{
            appIDs: [app_id],
            appID: app_id,
            components: [%{"/" => "/d/*"}, %{"/" => "/u/*"}],
            paths: ["/d/*", "/u/*"]
          }
        ]
      }
    })
  end

  # Browser fallback for shared links when the app isn't installed.
  def fallback(conn, _params) do
    html(conn, """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <title>HeadsUp Fantasy</title>
      <style>
        body { margin:0; font-family: -apple-system, Helvetica, Arial, sans-serif; background:#0f172a; color:#fff;
               display:flex; align-items:center; justify-content:center; min-height:100vh; text-align:center; }
        .card { padding: 40px 24px; max-width: 420px; }
        .mark { font-size: 72px; font-weight: 900; letter-spacing: -2px;
                background: linear-gradient(#5eead4, #4ade80); -webkit-background-clip: text; background-clip: text; color: transparent; }
        h1 { font-size: 22px; margin: 8px 0 12px; }
        p { color: #94a3b8; line-height: 1.5; margin: 0 0 8px; }
        .pill { display:inline-block; margin-top: 18px; padding: 12px 22px; border-radius: 999px;
                background:#4ade80; color:#0f172a; font-weight: 700; text-decoration: none; }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="mark">HU</div>
        <h1>You've been challenged on HeadsUp Fantasy</h1>
        <p>Head-to-head fantasy duels with your friends: draft live, talk trash, settle it on real games.</p>
        <p>If you have the app, this link opens it. If not — ask whoever sent this for an invite; the beta is invite-only for now.</p>
      </div>
    </body>
    </html>
    """)
  end
end
