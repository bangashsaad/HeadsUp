defmodule HeadsUpWeb.SessionHTML do
  use HeadsUpWeb, :html

  # The signed-out frame lives with the other layouts.
  import HeadsUpWeb.Layouts, only: [auth_shell: 1]

  embed_templates "session_html/*"
end
