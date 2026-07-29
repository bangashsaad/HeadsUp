defmodule HeadsUpWeb.LegalController do
  @moduledoc """
  The two public pages App Review requires a live URL for: a privacy policy
  and a support page. Served from our own domain so the links never rot.

  Keep these HONEST — they must describe what the app actually does. If we
  start collecting something new (analytics, crash reports, payments), the
  policy changes in the same commit.
  """
  use HeadsUpWeb, :controller

  @updated "July 28, 2026"

  defp support_email,
    do: Application.get_env(:heads_up, :support_email, "nyel.bangash@richmond.edu")

  def privacy(conn, _params) do
    html(conn, page("Privacy Policy", """
    <p class="upd">Last updated #{@updated}</p>

    <p>Heads Up Fantasy is a head-to-head fantasy sports game you play with
    friends. This policy explains exactly what we store, why, and what you can
    do about it. It is deliberately short, because we collect very little.</p>

    <h2>What we collect</h2>
    <ul>
      <li><b>Your account</b> — username, email address, and a one-way
      cryptographic hash of your password. We never store your actual password
      and cannot recover it.</li>
      <li><b>How you play</b> — duels, drafts, picks, results, and your
      in-app coin balance and history.</li>
      <li><b>Your friends and groups</b> — who you're connected to, and the
      private groups you sort them into. Group names are visible only to you.</li>
      <li><b>Activity time</b> — a timestamp of when you last used the app, so
      friends can see whether you're around.</li>
      <li><b>Push token</b> — an anonymous device identifier from Apple or
      Google, only if you allow notifications.</li>
    </ul>

    <h2>What we do NOT collect</h2>
    <ul>
      <li>No payment or financial information. Coins are free, cannot be
      bought, cashed out, or transferred, and have no monetary value.</li>
      <li>No location data.</li>
      <li>No contacts, photos, microphone, or camera access.</li>
      <li>No advertising identifiers. We do not sell or share your data, and
      there are no third-party ad or tracking networks in the app.</li>
    </ul>

    <h2>Who else touches your data</h2>
    <p>Only the services required to run the app: our hosting provider and
    database, Apple's and Google's push notification services (for
    notifications you opted into), and an email provider used solely to send
    verification and password-reset codes. Sports statistics come from public
    feeds and contain no information about you.</p>

    <h2>Your control</h2>
    <p>You can delete your account at any time from <b>Settings &rarr; Delete
    account</b>. Deletion erases your username, email, password, and push
    token, removes your friendships and private groups, cancels any live duels
    and refunds their stakes. Finished duels remain in your opponents' history
    under an anonymous name, because those results are their records too.</p>

    <p>You can turn off notifications at any time in your device settings.</p>

    <h2>Children</h2>
    <p>Heads Up Fantasy is not directed to children under 13, and we do not
    knowingly collect information from them.</p>

    <h2>Security</h2>
    <p>All traffic is encrypted in transit. Passwords are hashed with bcrypt.
    Login sessions expire after prolonged inactivity.</p>

    <h2>Contact</h2>
    <p>Questions about your data, or want a copy of it? Email
    <a href="mailto:#{support_email()}">#{support_email()}</a>.</p>
    """))
  end

  def support(conn, _params) do
    html(conn, page("Support", """
    <p class="upd">We read every message.</p>

    <p><b>Email:</b> <a href="mailto:#{support_email()}">#{support_email()}</a></p>
    <p>Tell us your username and what happened — screenshots help. We usually
    reply within a couple of days.</p>

    <h2>Common questions</h2>

    <h3>I didn't get my verification code</h3>
    <p>Check your spam folder first. In the app, tap <b>Send a new code</b> —
    codes expire after 15 minutes. If it still doesn't arrive, email us and
    we'll verify you by hand.</p>

    <h3>I forgot my password</h3>
    <p>Tap <b>Forgot password?</b> on the login screen. We'll email you a
    six-digit code to set a new one.</p>

    <h3>What are coins?</h3>
    <p>Coins are a free scorekeeping currency for friendly stakes. They cannot
    be purchased, cashed out, or transferred, and they have no monetary value.
    Everyone starts with a grant, and a small daily bonus tops you up if you
    run low.</p>

    <h3>How is my duel scored?</h3>
    <p>From the real box scores of the games on the slate you picked, using the
    scoring chart shown on the challenge before anyone accepts. Winners are
    declared automatically once those games go final.</p>

    <h3>Nobody accepted my challenge</h3>
    <p>Unanswered challenges expire automatically after about a day, and any
    coins you staked come straight back to you.</p>

    <h3>How do I delete my account?</h3>
    <p>In the app: <b>You &rarr; Settings &rarr; Delete account</b>. It asks
    for your password and is permanent. Live duels are cancelled and every
    stake is refunded.</p>
    """))
  end

  # One shared shell so both pages match the app's look on any device.
  defp page(title, body) do
    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <title>#{title} · Heads Up Fantasy</title>
      <style>
        :root { color-scheme: dark; }
        body {
          margin: 0; padding: 40px 22px 72px;
          background: #0A0B10; color: #F4F5F7;
          font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .wrap { max-width: 640px; margin: 0 auto; }
        .mark { font-weight: 800; letter-spacing: -0.5px; font-size: 20px; margin-bottom: 4px; }
        .mark span { color: #C8FF2E; }
        h1 { font-size: 27px; margin: 18px 0 6px; letter-spacing: -0.4px; }
        h2 { font-size: 17px; margin: 30px 0 8px; color: #C8FF2E; }
        h3 { font-size: 15px; margin: 22px 0 4px; }
        p, li { color: #C7CCD8; }
        li { margin-bottom: 7px; }
        b { color: #F4F5F7; }
        a { color: #C8FF2E; }
        .upd { color: #8B91A7; font-size: 14px; }
        footer { margin-top: 44px; border-top: 1px solid #252A3A; padding-top: 16px; color: #565D73; font-size: 13px; }
      </style>
    </head>
    <body>
      <div class="wrap">
        <div class="mark">HEADS<span>UP</span></div>
        <h1>#{title}</h1>
        #{body}
        <footer>
          Heads Up Fantasy · <a href="/privacy">Privacy</a> · <a href="/support">Support</a>
        </footer>
      </div>
    </body>
    </html>
    """
  end
end
