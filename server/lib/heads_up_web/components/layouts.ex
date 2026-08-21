defmodule HeadsUpWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HeadsUpWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <img src={~p"/images/logo.svg"} width="36" />
          <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li>
            <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
          </li>
          <li>
            <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
              Get Started <span aria-hidden="true">&rarr;</span>
            </a>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-20 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  The frame for signed-out pages: sign in, sign up. Deliberately narrow and
  centred — on the reach path this is the only thing between a stranger who
  followed a link and a draft, so it carries the brand and nothing else.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :inner_block, required: true

  def auth_shell(assigns) do
    ~H"""
    <main class="flex min-h-dvh flex-col items-center justify-center bg-[#0A0B10] px-5 py-12">
      <.flash_group :if={assigns[:flash]} flash={@flash} />
      <div class="w-full max-w-sm">
        <.link navigate="/" class="mb-8 block text-center">
          <span class="text-2xl font-black uppercase tracking-tight text-[#F4F5F7]">
            Heads<span class="text-[#C8FF2E]">Up</span>
          </span>
        </.link>

        <h1 class="text-center text-xl font-black text-[#F4F5F7]">{@title}</h1>
        <p :if={@subtitle} class="mt-1.5 mb-7 text-center text-sm text-[#8B91A7]">{@subtitle}</p>

        {render_slot(@inner_block)}
      </div>
    </main>
    """
  end

  @doc """
  The design's app shell, whole this time: the 230px sidebar with its six-item
  icon nav (DUELS count, LIVE badge), the pulsing + NEW CHALLENGE button, the
  and the profile row with your record — plus the marquee
  ticker across the top of the main column. Phones collapse to a top bar,
  keeping the ticker (it is the piece that makes the app feel alive).

  Ticker/nav/record assigns come from `HeadsUpWeb.ShellHook`; pages that render
  outside the authenticated live_session simply omit them and the shell
  degrades to chrome without badges.
  """
  attr :current_user, :map, default: nil
  attr :flash, :map, default: %{}
  attr :shell, :map, default: %{}
  slot :inner_block, required: true

  def shell(assigns) do
    assigns =
      Phoenix.Component.assign(assigns,
        ticker: Map.get(assigns.shell, :ticker, []),
        nav_active: Map.get(assigns.shell, :active),
        nav_duel_count: Map.get(assigns.shell, :duel_count, 0),
        nav_live_path: Map.get(assigns.shell, :live_path),
        nav_live?: Map.get(assigns.shell, :live?, false),
        nav_draft_path: Map.get(assigns.shell, :draft_path),
        nav_req_count: Map.get(assigns.shell, :req_count, 0),
        shell_record: Map.get(assigns.shell, :record)
      )

    ~H"""
    <div class="flex min-h-dvh bg-[#07080C] text-[#F4F5F7]">
      <%!-- sidebar (the design's, verbatim) — desktop only --%>
      <aside class="sticky top-0 hidden h-dvh w-[230px] flex-none flex-col border-r border-[#1A1E2B] bg-[#0D0F16] lg:flex" style="box-sizing:border-box">
        <.link navigate="/app" style="cursor:pointer;padding:24px 22px 20px;display:flex;flex-direction:column">
          <span class="hu-black" style="font-size:23px;letter-spacing:-.5px;line-height:1">
            <span style="color:#F4F5F7">HEADS</span><span style="color:var(--acc,#C8FF2E)">UP</span>
          </span>
          <span style="font-size:9px;font-weight:800;letter-spacing:3.5px;color:#565D73;margin-top:3px">FANTASY DUELS</span>
        </.link>

        <nav style="padding:0 12px;display:flex;flex-direction:column;gap:3px">
          <.nav_item navigate="/app" icon="home" label="HOME" active={@nav_active == :home} />
          <.nav_item navigate="/app/duels" icon="flame" label="DUELS" count={@nav_duel_count} active={@nav_active == :duels} />
          <.nav_item navigate={@nav_draft_path || "/app/draft"} icon="timer" label="DRAFT" active={@nav_active == :draft} />
          <.nav_item navigate={@nav_live_path || "/app/live"} icon="pulse" label="LIVE" live={@nav_live?} active={@nav_active == :live} />
          <.nav_item navigate="/app/games" icon="basketball" label="SCOREBOARD" active={@nav_active == :players} />
          <.nav_item navigate="/app/friends" icon="people" label="FRIENDS" count={@nav_req_count} active={@nav_active == :friends} />
          <.nav_item navigate="/app/you" icon="person-circle" label="YOU" active={@nav_active == :profile} />
        </nav>

        <div style="padding:16px 12px">
          <.link
            navigate="/app/new"
            class="hu-cond huw-pulse"
            style="cursor:pointer;display:block;background:var(--acc,#C8FF2E);color:#0A0B10;border-radius:12px;padding:12px;text-align:center;font-size:17px;letter-spacing:.5px"
          >
            + NEW CHALLENGE
          </.link>
        </div>


        <.link
          :if={@current_user}
          navigate="/app/you"
          style="cursor:pointer;margin-top:auto;padding:15px 14px;border-top:1px solid #1A1E2B;display:flex;align-items:center;gap:10px"
        >
          <div style="width:36px;height:36px;flex:none;border-radius:11px;background:linear-gradient(135deg,rgba(200,255,46,.22),#7C5CFF33);border:1px solid rgba(200,255,46,.4);display:flex;align-items:center;justify-content:center">
            <span style="color:var(--acc,#C8FF2E);font-weight:800;font-size:14px">
              {@current_user.username |> String.first() |> String.upcase()}
            </span>
          </div>
          <div style="display:flex;flex-direction:column;min-width:0">
            <span style="font-weight:800;font-size:13px">{@current_user.username}</span>
            <span style="font-size:11px;color:#8B91A7;font-weight:600">{record_line(@shell_record)}</span>
          </div>
          <span style="margin-left:auto;width:14px;height:14px;background:#565D73;-webkit-mask:url('/icons/person.svg') center/contain no-repeat;mask:url('/icons/person.svg') center/contain no-repeat">
          </span>
        </.link>
        <.link
          :if={@current_user}
          href="/logout"
          method="delete"
          style="padding:6px 22px 14px;font-size:10px;font-weight:800;letter-spacing:.5px;color:#565D73"
        >
          SIGN OUT
        </.link>
      </aside>

      <div class="min-w-0 flex-1 flex flex-col">
        <%!-- Phone chrome: wordmark + horizontal nav --%>
        <header class="sticky top-0 z-20 border-b border-[#1A1E2B] bg-[#0A0B10]/95 backdrop-blur lg:hidden">
          <div class="flex items-center justify-between px-4 py-3">
            <.link navigate="/app" class="hu-black text-lg leading-none tracking-[-0.5px]">
              <span class="text-[#F4F5F7]">HEADS</span><span class="text-[#C8FF2E]">UP</span>
            </.link>
            <nav :if={@current_user} class="flex items-center gap-3.5">
              <.link navigate="/app" class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                Home
              </.link>
              <.link navigate="/app/duels" class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                Duels
              </.link>
              <.link navigate={@nav_draft_path || "/app/draft"} class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                Draft
              </.link>
              <.link
                :if={@nav_live?}
                navigate={@nav_live_path}
                class="text-xs font-black uppercase tracking-wide text-[#FF4557]"
              >
                Live
              </.link>
              <.link navigate="/app/games" class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                Scores
              </.link>
              <.link navigate="/app/friends" class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                Crew
              </.link>
              <.link navigate="/app/new" class="text-xs font-black uppercase tracking-wide text-[#C8FF2E] hover:brightness-110">
                + New
              </.link>
              <.link navigate="/app/you" class="text-xs font-black uppercase tracking-wide text-[#8B91A7] hover:text-[#F4F5F7]">
                You
              </.link>
            </nav>
          </div>
        </header>

        <%!-- the marquee ticker (the design's slate line) --%>
        <div :if={@ticker != []} style="border-bottom:1px solid #1A1E2B;background:#0D0F16;overflow:hidden;white-space:nowrap">
          <div style="display:inline-flex;gap:34px;padding:9px 0;animation:huw-marq 26s linear infinite">
            <span
              :for={t <- @ticker ++ @ticker}
              style="font-family:'Barlow Condensed',sans-serif;font-weight:700;font-size:15px;display:inline-flex;gap:9px;align-items:center"
            >
              <span style={"color:#{t.tag_color};font-weight:800"}>{t.tag}</span>
              <span style="color:#F4F5F7">{t.line}</span>
              <span :if={t.meta != ""} style="color:#565D73">{t.meta}</span>
            </span>
          </div>
        </div>

        <.flash_group flash={@flash} />
        <main style="padding:28px 16px 50px" class="lg:px-[34px]">{render_slot(@inner_block)}</main>
      </div>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: 0
  attr :live, :boolean, default: false
  attr :active, :boolean, default: false

  defp nav_item(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class="hover:bg-[#151827]"
      style={"cursor:pointer;display:flex;align-items:center;gap:12px;padding:11px 14px;border-radius:10px;background:#{if @active, do: "rgba(200,255,46,.08)", else: "transparent"};border:1px solid #{if @active, do: "rgba(200,255,46,.35)", else: "transparent"}"}
    >
      <span style={"width:16px;height:16px;flex:none;background:#{if @active, do: "var(--acc,#C8FF2E)", else: "#8B91A7"};-webkit-mask:url('/icons/#{@icon}.svg') center/contain no-repeat;mask:url('/icons/#{@icon}.svg') center/contain no-repeat"}>
      </span>
      <span style={"font-weight:800;font-size:12.5px;letter-spacing:.5px;color:#{if @active, do: "var(--acc,#C8FF2E)", else: "#B9BECF"}"}>{@label}</span>
      <span
        :if={@live}
        style="margin-left:auto;display:inline-flex;align-items:center;gap:5px;background:rgba(255,69,87,.15);border:1px solid #FF4557;border-radius:999px;padding:2px 7px"
      >
        <span class="huw-blink" style="width:5px;height:5px;border-radius:3px;background:#FF4557"></span>
        <span style="color:#FF4557;font-size:9px;font-weight:900;letter-spacing:1px">LIVE</span>
      </span>
      <span :if={!@live and @count > 0} style="margin-left:auto;font-size:10px;font-weight:800;color:#565D73">{@count}</span>
    </.link>
    """
  end

  defp record_line(nil), do: "duelist"

  defp record_line(r) do
    streak =
      case r.streak do
        %{count: c, type: "win"} when c >= 2 -> " · 🔥 W#{c}"
        _ -> ""
      end

    "#{r.wins}–#{r.losses}#{streak}"
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
