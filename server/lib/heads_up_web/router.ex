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

  scope "/", HeadsUpWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Public API routes (no login required)
  scope "/api", HeadsUpWeb do
    pipe_through :api

    get "/hello", HelloController, :index
    post "/register", AuthController, :register
    post "/login", AuthController, :login
  end

  # API routes that require a valid login token
  scope "/api", HeadsUpWeb do
    pipe_through [:api, :api_authenticated]

    get "/me", AuthController, :me
    put "/me/password", AuthController, :change_password
    delete "/logout", AuthController, :logout

    # Competitive stats + home dashboard
    get "/me/stats", StatsController, :me
    get "/me/achievements", StatsController, :achievements
    get "/leaderboard", StatsController, :leaderboard
    get "/home", HomeController, :index

    # Friends
    get "/users/search", UserController, :search
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
    get "/games/:event_id/boxscore", GameController, :boxscore

    # Challenges (duels)
    get "/duels", DuelController, :index
    post "/duels", DuelController, :create
    get "/duels/:id", DuelController, :show
    get "/duels/:id/result", DuelController, :result
    get "/duels/:id/live", DuelController, :live
    post "/duels/:id/accept", DuelController, :accept
    post "/duels/:id/decline", DuelController, :decline
    post "/duels/:id/cancel", DuelController, :cancel
    post "/duels/:id/counter", DuelController, :counter
    post "/duels/:id/rematch", DuelController, :rematch
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
