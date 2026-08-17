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

  # The current preview build's .ipa (public EAS artifact). Update on each
  # preview rebuild. Served via Apple's itms-services OTA install so testers
  # never need an Expo account — install works for the registered devices only.
  @ipa_url "https://expo.dev/artifacts/eas/stq16Sm7r17GmmX5FX_2BHU6Txs92vTci8Wz7I2SvR0.ipa"
  @app_version "1.0.1"

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

  # Self-hosted install page: taps straight into Apple's OTA install flow.
  def install(conn, _params) do
    # The stale ad-hoc IPA flow is retired: /install now lands on TestFlight
    # once the public link exists, and the app-gate page until then.
    case Application.get_env(:heads_up, :testflight_url) do
      nil -> redirect(conn, to: "/get-the-app")
      url -> redirect(conn, external: url)
    end
  end

  # Apple OTA manifest pointing at the current build's ipa.
  def manifest(conn, _params) do
    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>items</key>
      <array>
        <dict>
          <key>assets</key>
          <array>
            <dict>
              <key>kind</key><string>software-package</string>
              <key>url</key><string>#{@ipa_url}</string>
            </dict>
          </array>
          <key>metadata</key>
          <dict>
            <key>bundle-identifier</key><string>#{@bundle_id}</string>
            <key>bundle-version</key><string>#{@app_version}</string>
            <key>kind</key><string>software</string>
            <key>title</key><string>HeadsUp Fantasy</string>
          </dict>
        </dict>
      </array>
    </dict>
    </plist>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
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
