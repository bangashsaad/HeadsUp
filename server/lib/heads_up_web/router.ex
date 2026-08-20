defmodule HeadsUpWeb.Router do
  use HeadsUpWeb, :router

  import HeadsUpWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HeadsUpWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :fetch_api_user
  end

  pipeline :api_authenticated do
    plug :require_authenticated_user
  end

  # The browser app. Same token store as the phone; the cookie is just a
  # different way to carry it.
  pipeline :web do
    plug :fetch_web_user
  end

  # Phones get the app-gate page instead of the desktop site (escape-hatch
  # cookie turns it off). Landing, legal, and logout stay ungated.
  pipeline :phone_gate do
    plug HeadsUpWeb.MobileGate
  end

  scope "/", HeadsUpWeb do
    # :web so a signed-in visitor is recognised and sent to their duels rather
    # than being pitched the product they already use.
    pipe_through [:browser, :web]

    get "/get-the-app", GateController, :show
    get "/get-the-app/continue", GateController, :continue
  end

  # The landing gates too: a phone's first touch is the gate page, which IS
  # the mobile pitch. Crawlers pass (the plug lets bots through), so search
  # keeps indexing the real landing.
  scope "/", HeadsUpWeb do
    pipe_through [:browser, :web, :phone_gate]

    get "/", PageController, :home
  end

  scope "/", HeadsUpWeb do
    pipe_through [:browser, :web, :phone_gate, :redirect_if_web_user]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/signup", SessionController, :new_signup
    post "/signup", SessionController, :signup
    get "/forgot-password", SessionController, :forgot
    post "/forgot-password", SessionController, :send_reset
    get "/reset-password", SessionController, :reset
    post "/reset-password", SessionController, :do_reset
  end

  scope "/", HeadsUpWeb do
    pipe_through [:browser, :web]

    delete "/logout", SessionController, :delete
  end

  scope "/", HeadsUpWeb do
    pipe_through [:browser, :web, :phone_gate, :require_web_user]

    live_session :authenticated,
      on_mount: [{HeadsUpWeb.UserAuth, :ensure_authenticated}, {HeadsUpWeb.ShellHook, :default}],
      layout: {HeadsUpWeb.Layouts, :root} do
      live "/app", HomeLive, :index
      live "/app/verify", VerifyLive, :index
      live "/app/coins", CoinsLive, :index
      live "/app/duels", DuelsLive, :index
      live "/app/duels/:id", DuelDetailLive, :show
      live "/app/new", NewChallengeLive, :new
      live "/app/draft", DraftHubLive, :index
      live "/app/draft/:id", DraftLive, :show
      live "/app/live", LiveHubLive, :index
      live "/app/live/:id", LiveLive, :show
      live "/app/results/:id", ResultsLive, :show
      live "/app/you", YouLive, :index
      live "/app/friends", FriendsLive, :index
      live "/app/games", GamesLive, :index
      live "/app/games/:id", GameDetailLive, :show
    end
  end

  # Universal links: Apple's association file + browser fallbacks for shared
  # duel/profile links. Public, no session plumbing.
  scope "/", HeadsUpWeb do
    get "/.well-known/apple-app-site-association", DeepLinkController, :aasa
    get "/apple-app-site-association", DeepLinkController, :aasa
    get "/d/:id", DeepLinkController, :fallback
    get "/u/:username", DeepLinkController, :fallback
    get "/privacy", LegalController, :privacy
    get "/support", LegalController, :support
    get "/install", DeepLinkController, :install
    get "/install/manifest.plist", DeepLinkController, :manifest
  end

  # Public API routes (no login required)
  scope "/api", HeadsUpWeb do
    pipe_through :api

    get "/hello", HelloController, :index
    # Dependency health. 503 here fails the keepalive workflow, which is how
    # a degraded server reaches a human.
    get "/health", HealthController, :index
    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/password/forgot", AuthController, :forgot_password
    post "/password/reset", AuthController, :reset_password
  end

  # API routes that require a valid login token
  scope "/api", HeadsUpWeb do
    pipe_through [:api, :api_authenticated]

    get "/me", AuthController, :me
    put "/me/password", AuthController, :change_password
    delete "/me", AuthController, :delete_account
    post "/me/verify", AuthController, :verify_email
    post "/me/verify/resend", AuthController, :resend_verification
    put "/me/push_token", AuthController, :push_token
    delete "/logout", AuthController, :logout

    # Coins (the in-house currency): wallet balance + movement history
    get "/coins", CoinController, :index

    # Competitive stats + home dashboard
    get "/me/stats", StatsController, :me
    get "/rivals/:id", RivalController, :show
    get "/me/achievements", StatsController, :achievements
    get "/leaderboard", StatsController, :leaderboard
    get "/home", HomeController, :index

    # Friends
    get "/users/search", UserController, :search
    get "/users/:id", UserController, :show
    get "/blocks", UserController, :blocked
    post "/users/:id/block", UserController, :block
    delete "/users/:id/block", UserController, :unblock
    get "/friend-groups", FriendGroupController, :index
    post "/friend-groups", FriendGroupController, :create
    put "/friend-groups/:id", FriendGroupController, :update
    put "/friend-groups/:id/members", FriendGroupController, :set_members
    delete "/friend-groups/:id", FriendGroupController, :delete

    get "/friends", FriendshipController, :index
    post "/friends", FriendshipController, :create
    get "/friends/requests", FriendshipController, :requests
    post "/friends/requests/:id/accept", FriendshipController, :accept
    delete "/friends/requests/:id", FriendshipController, :delete

    # Sports / draft pool
    get "/players", PlayerController, :index
    get "/players/search", PlayerController, :search
    get "/players/:id/profile", PlayerController, :profile
    get "/games/upcoming", GameController, :upcoming
    get "/games/scoreboard", GameController, :scoreboard
    get "/sports/status", GameController, :season
    get "/sports/:sport/slates", GameController, :slates
    get "/games/:event_id/boxscore", GameController, :boxscore

    # Challenges (duels)
    get "/duels", DuelController, :index
    post "/duels", DuelController, :create
    get "/duels/:id", DuelController, :show
    get "/duels/:id/result", DuelController, :result
    get "/duels/:id/live", DuelController, :live
    get "/duels/:id/messages", DuelController, :messages
    post "/duels/:id/messages", DuelController, :post_message
    post "/duels/:id/accept", DuelController, :accept
    post "/duels/:id/decline", DuelController, :decline
    post "/duels/:id/cancel", DuelController, :cancel
    post "/duels/:id/counter", DuelController, :counter
    post "/duels/:id/rematch", DuelController, :rematch
    post "/duels/:id/start", DuelController, :start
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:heads_up, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HeadsUpWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
