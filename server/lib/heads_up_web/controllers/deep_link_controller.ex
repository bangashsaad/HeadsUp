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
  def fallback(conn, %{"id" => id}) do
    # Duel links route INTO the app: the duel-detail page is party-scoped and
    # login stores the return path, so a signed-out click lands here after
    # signing in. Phones meet the app gate first — the intended funnel.
    redirect(conn, to: "/app/duels/#{id}")
  end

  def fallback(conn, %{"username" => username}) do
    redirect(conn, to: "/app/friends?q=#{URI.encode_www_form(username)}")
  end
end
