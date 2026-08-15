defmodule HeadsUpWeb.FriendsLive do
  @moduledoc """
  The FRIENDS tab, from Saad's design drop: the crew list with overall records
  and group-filter pills, an edit mode where clicking friends checks them in
  and out of a group, live username search that surfaces strangers with a
  SEND REQUEST button, the WANTS IN inbox, and private friend groups with
  inline creation. Everything rides the existing Social + Stats contexts —
  the same calls the phone makes.
  """
  use HeadsUpWeb, :live_view

  alias HeadsUp.{Social, Stats}

  # The app's deterministic avatar tints (mobile/src/theme.js avatarColor),
  # as {wash, ink} pairs the design renders.
  @tints [
    {"rgba(255,77,141,.18)", "#FF4D8D"},
    {"rgba(34,229,255,.15)", "#22E5FF"},
    {"rgba(57,217,138,.16)", "#39D98A"},
    {"rgba(255,176,33,.16)", "#FFB021"},
    {"rgba(124,92,255,.2)", "#A794FF"},
    {"rgba(92,168,255,.18)", "#5CA8FF"},
    {"rgba(255,122,26,.16)", "#FF7A1A"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Friends", q: "", tab: :all, edit: nil, results: [], sent: MapSet.new())
     |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    records =
      user
      |> Stats.leaderboard()
      |> Map.new(&{&1.user.id, &1})

    assign(socket,
      friends: Social.list_friends(user),
      records: records,
      requests: Social.list_incoming_requests(user),
      groups: Social.list_friend_groups(user)
    )
  end

  # --- search -----------------------------------------------------------------

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    q = String.trim_leading(q)

    results =
      if String.length(String.trim(q)) >= 2 do
        Social.search_users(q, socket.assigns.current_user)
      else
        []
      end

    {:noreply, assign(socket, q: q, results: results)}
  end

  def handle_event("send-request", %{"id" => id}, socket) do
    case Social.send_friend_request(socket.assigns.current_user, id) do
      {:ok, _} ->
        {:noreply, update(socket, :sent, &MapSet.put(&1, String.to_integer(id)))}

      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "That request can't be sent.")}
    end
  end

  def handle_event("accept-search", %{"fid" => fid}, socket) do
    case Social.accept_friend_request(socket.assigns.current_user, fid) do
      {:ok, _} ->
        {:noreply, socket |> load() |> assign(results: rerun_search(socket)) |> sync_req_badge()}

      _ ->
        {:noreply, put_flash(socket, :error, "That request is gone.")}
    end
  end

  # --- requests inbox ---------------------------------------------------------

  def handle_event("request-accept", %{"id" => id}, socket) do
    case Social.accept_friend_request(socket.assigns.current_user, id) do
      {:ok, _} -> {:noreply, socket |> load() |> sync_req_badge()}
      _ -> {:noreply, put_flash(socket, :error, "That request is gone.")}
    end
  end

  def handle_event("request-decline", %{"id" => id}, socket) do
    _ = Social.delete_friendship(socket.assigns.current_user, id)
    {:noreply, socket |> load() |> sync_req_badge()}
  end

  # --- group tabs + edit mode -------------------------------------------------

  def handle_event("tab", %{"id" => "all"}, socket),
    do: {:noreply, assign(socket, tab: :all, edit: nil)}

  def handle_event("tab", %{"id" => id}, socket),
    do: {:noreply, assign(socket, tab: String.to_integer(id), edit: nil)}

  def handle_event("edit-group", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, edit: (socket.assigns.edit == id && nil) || id, tab: :all)}
  end

  def handle_event("edit-done", _params, socket), do: {:noreply, assign(socket, edit: nil)}

  def handle_event("toggle-member", %{"id" => id}, socket) do
    %{edit: gid, groups: groups, current_user: user} = socket.assigns

    with %{member_ids: ids} <- Enum.find(groups, &(&1.id == gid)) do
      id = String.to_integer(id)
      next = if id in ids, do: List.delete(ids, id), else: ids ++ [id]
      {:ok, _} = Social.set_friend_group_members(user, gid, next)
    end

    {:noreply, assign(socket, groups: Social.list_friend_groups(user))}
  end

  def handle_event("create-group", %{"name" => name}, socket) do
    name = name |> String.trim() |> String.upcase()

    cond do
      name == "" ->
        {:noreply, socket}

      true ->
        case Social.create_friend_group(socket.assigns.current_user, name) do
          {:ok, group} ->
            {:noreply,
             socket
             |> assign(groups: Social.list_friend_groups(socket.assigns.current_user), edit: group.id, tab: :all)
             |> put_flash(:info, "#{name} created — click friends to add them.")}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "You already have a group named #{name}.")}
        end
    end
  end

  # Accepting from search or inbox changes the sidebar badge; keep it honest
  # without a full remount.
  defp sync_req_badge(socket) do
    shell = socket.assigns[:shell] || %{}
    assign(socket, :shell, Map.put(shell, :req_count, length(socket.assigns.requests)))
  end

  defp rerun_search(socket) do
    q = socket.assigns.q

    if String.length(String.trim(q)) >= 2,
      do: Social.search_users(q, socket.assigns.current_user),
      else: []
  end

  # --- derived rows -----------------------------------------------------------

  defp crew_rows(assigns) do
    %{friends: friends, records: records, groups: groups, q: q, tab: tab, edit: edit} = assigns
    frag = q |> String.trim() |> String.downcase()

    friends
    |> Enum.filter(&(frag == "" or String.contains?(String.downcase(&1.username), frag)))
    |> Enum.filter(fn f ->
      # Edit mode lists everyone so anyone can be added to the group.
      edit != nil or tab == :all or f.id in member_ids(groups, tab)
    end)
    |> Enum.map(fn f ->
      rec = Map.get(records, f.id, %{wins: 0, losses: 0})
      in_group = edit && f.id in member_ids(groups, edit)

      %{
        user: f,
        groups_line: groups_line(groups, f.id),
        rec: "#{rec.wins}–#{rec.losses}",
        rec_ink: if(rec.wins >= rec.losses, do: "var(--acc,#C8FF2E)", else: "#FF4557"),
        in_group: in_group
      }
    end)
  end

  defp member_ids(groups, gid) do
    case Enum.find(groups, &(&1.id == gid)) do
      %{member_ids: ids} -> ids
      _ -> []
    end
  end

  defp groups_line(groups, user_id) do
    case for g <- groups, user_id in g.member_ids, do: g.name do
      [] -> "No groups yet"
      names -> Enum.join(names, " · ")
    end
  end

  # Search results that aren't already crew. Friends matching the query are
  # already visible in the crew list above.
  defp stranger_rows(assigns) do
    assigns.results
    |> Enum.reject(&(&1.relationship == "friends"))
    |> Enum.map(fn r ->
      sent = r.relationship == "request_sent" or MapSet.member?(assigns.sent, r.user.id)

      %{
        user: r.user,
        friendship_id: r.friendship_id,
        asked_first: r.relationship == "request_received",
        sent: sent,
        meta: stranger_meta(r.user)
      }
    end)
  end

  defp stranger_meta(user) do
    rec = Stats.record_for(user.id)

    if rec.played > 0 do
      "#{rec.wins}–#{rec.losses} · plays #{favorite_league(user.id)}"
    else
      "new here"
    end
  end

  defp favorite_league(user_id) do
    import Ecto.Query

    from(d in HeadsUp.Contests.Duel,
      where: d.challenger_id == ^user_id or d.opponent_id == ^user_id,
      group_by: d.sport,
      order_by: [desc: count(d.id)],
      select: d.sport,
      limit: 1
    )
    |> HeadsUp.Repo.one()
    |> case do
      nil -> "nobody yet"
      sport -> String.upcase(sport)
    end
  end

  defp tint(username) do
    Enum.at(@tints, :erlang.phash2(username, length(@tints)))
  end

  defp initial(username), do: username |> String.first() |> String.upcase()

  defp edit_group_name(groups, gid) do
    case Enum.find(groups, &(&1.id == gid)) do
      %{name: name} -> name
      _ -> ""
    end
  end

  # --- render -----------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        crew: crew_rows(assigns),
        strangers: stranger_rows(assigns),
        frag?: String.length(String.trim(assigns.q)) >= 2
      )

    ~H"""
    <Layouts.shell current_user={@current_user} flash={@flash} shell={assigns[:shell] || %{}}>
      <div style="flex:1;display:flex;flex-direction:column;gap:16px;max-width:1060px;width:100%;margin:0 auto;box-sizing:border-box;animation:huw-rise .3s ease">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap">
          <div style="display:flex;flex-direction:column">
            <span class="hu-cond" style="font-size:24px;letter-spacing:.5px">FRIENDS</span>
            <span style="font-size:11.5px;color:#8B91A7;font-weight:600">Your crew, your groups, your next victims.</span>
          </div>
          <form
            phx-change="search"
            phx-submit="search"
            style="display:flex;align-items:center;gap:8px;background:#12141D;border:1px solid #252A3A;border-radius:999px;padding:9px 16px;width:min(280px,100%);box-sizing:border-box"
          >
            <span style="width:14px;height:14px;flex:none;background:#565D73;-webkit-mask:url('/icons/bd194911.svg') center/contain no-repeat;mask:url('/icons/bd194911.svg') center/contain no-repeat">
            </span>
            <input
              type="text"
              name="q"
              value={@q}
              autocomplete="off"
              phx-debounce="300"
              placeholder="Search usernames…"
              style="flex:1;min-width:0;background:transparent;border:none;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:13px;outline:none"
            />
          </form>
        </div>

        <div style="display:flex;flex-wrap:wrap;gap:16px;align-items:flex-start">
          <%!-- crew list --%>
          <div style="flex:1.5;min-width:min(400px,100%);border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
            <div style="padding:13px 18px;border-bottom:1px solid #1A1E2B;display:flex;flex-wrap:wrap;align-items:center;gap:10px">
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">YOUR CREW · {length(@friends)}</span>
              <div style="display:flex;flex-wrap:wrap;gap:6px;margin-left:6px">
                <span
                  phx-click="tab"
                  phx-value-id="all"
                  class="hover:brightness-125"
                  style={"cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.5px;color:#{if @edit == nil and @tab == :all, do: "#A794FF", else: "#8B91A7"};background:#{if @edit == nil and @tab == :all, do: "rgba(124,92,255,.15)", else: "transparent"};border:1px solid #{if @edit == nil and @tab == :all, do: "#7C5CFF", else: "#252A3A"};border-radius:999px;padding:5px 13px;white-space:nowrap"}
                >
                  ALL
                </span>
                <span
                  :for={g <- @groups}
                  phx-click="tab"
                  phx-value-id={g.id}
                  class="hover:brightness-125"
                  style={"cursor:pointer;font-size:10.5px;font-weight:800;letter-spacing:.5px;color:#{if @edit == nil and @tab == g.id, do: "#A794FF", else: "#8B91A7"};background:#{if @edit == nil and @tab == g.id, do: "rgba(124,92,255,.15)", else: "transparent"};border:1px solid #{if @edit == nil and @tab == g.id, do: "#7C5CFF", else: "#252A3A"};border-radius:999px;padding:5px 13px;white-space:nowrap"}
                >
                  {g.name}
                </span>
              </div>
            </div>

            <div
              :if={@edit != nil}
              style="padding:9px 18px;border-bottom:1px solid #1A1E2B;background:rgba(124,92,255,.08);display:flex;align-items:center;gap:10px"
            >
              <span style="font-size:10.5px;font-weight:900;letter-spacing:1px;color:#A794FF">EDITING {edit_group_name(@groups, @edit)}</span>
              <span style="font-size:11px;color:#8B91A7;font-weight:600">click a friend to add or remove them</span>
              <span
                phx-click="edit-done"
                class="hover:bg-[#1d1930]"
                style="cursor:pointer;margin-left:auto;border:1px solid #7C5CFF;color:#A794FF;font-size:10px;font-weight:900;letter-spacing:1px;border-radius:999px;padding:5px 14px"
              >
                DONE
              </span>
            </div>

            <%= for c <- @crew do %>
              <%= if @edit != nil do %>
                <div
                  phx-click="toggle-member"
                  phx-value-id={c.user.id}
                  class="hover:bg-[#151827]"
                  style="cursor:pointer;display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F"
                >
                  <div style={"width:38px;height:38px;flex:none;border-radius:11px;background:#{elem(tint(c.user.username), 0)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;color:#{elem(tint(c.user.username), 1)}"}>
                    {initial(c.user.username)}
                  </div>
                  <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                    <span style="font-weight:800;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c.user.username}</span>
                    <span style="font-size:10.5px;color:#565D73;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c.groups_line}</span>
                  </div>
                  <span style={"width:18px;height:18px;flex:none;border-radius:10px;border:1px solid #{if c.in_group, do: "var(--acc,#C8FF2E)", else: "#3A4157"};background:#{if c.in_group, do: "var(--acc,#C8FF2E)", else: "transparent"};display:flex;align-items:center;justify-content:center"}>
                    <span style={"width:11px;height:11px;background:#0A0B10;-webkit-mask:url('/icons/39393f35.svg') center/contain no-repeat;mask:url('/icons/39393f35.svg') center/contain no-repeat;opacity:#{if c.in_group, do: "1", else: "0"}"}>
                    </span>
                  </span>
                </div>
              <% else %>
                <div
                  class="hover:bg-[#151827]"
                  style="display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F"
                >
                  <.link
                    navigate={~p"/app/you?rival=#{c.user.id}"}
                    style="display:flex;align-items:center;gap:12px;min-width:0;flex:1;cursor:pointer"
                  >
                    <div style={"width:38px;height:38px;flex:none;border-radius:11px;background:#{elem(tint(c.user.username), 0)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;color:#{elem(tint(c.user.username), 1)}"}>
                      {initial(c.user.username)}
                    </div>
                    <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                      <span style="font-weight:800;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c.user.username}</span>
                      <span style="font-size:10.5px;color:#565D73;font-weight:700;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{c.groups_line}</span>
                    </div>
                  </.link>
                  <span class="hu-cond" style={"font-size:20px;color:#{c.rec_ink}"}>{c.rec}</span>
                  <.link
                    navigate={~p"/app/new?rival=#{c.user.id}"}
                    class="hu-cond hover:bg-[#1c220e]"
                    style="cursor:pointer;flex:none;border:1px solid var(--acc,#C8FF2E);color:var(--acc,#C8FF2E);font-size:13px;border-radius:999px;padding:6px 14px;white-space:nowrap"
                  >
                    CHALLENGE
                  </.link>
                </div>
              <% end %>
            <% end %>

            <div :if={@strangers != []}>
              <div style="padding:10px 18px 4px">
                <span style="font-size:9.5px;font-weight:900;letter-spacing:2px;color:#565D73">NOT IN YOUR CREW</span>
              </div>
              <div
                :for={s <- @strangers}
                style="display:flex;align-items:center;gap:12px;padding:11px 18px;border-bottom:1px solid #14171F"
              >
                <div style="width:38px;height:38px;flex:none;border-radius:11px;background:#1A1E2B;border:1px solid #252A3A;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:13px;color:#8B91A7">
                  {initial(s.user.username)}
                </div>
                <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                  <span style="font-weight:800;font-size:13.5px">{s.user.username}</span>
                  <span style="font-size:10.5px;color:#565D73;font-weight:700">{s.meta}</span>
                </div>
                <span
                  :if={s.asked_first}
                  phx-click="accept-search"
                  phx-value-fid={s.friendship_id}
                  class="hover:brightness-110"
                  style="cursor:pointer;flex:none;background:var(--acc,#C8FF2E);border:1px solid var(--acc,#C8FF2E);color:#0A0B10;font-size:10.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:7px 15px"
                >
                  THEY ASKED — ACCEPT
                </span>
                <span
                  :if={!s.asked_first and s.sent}
                  style="flex:none;background:transparent;border:1px solid #252A3A;color:#565D73;font-size:10.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:7px 15px"
                >
                  SENT ✓
                </span>
                <span
                  :if={!s.asked_first and !s.sent}
                  phx-click="send-request"
                  phx-value-id={s.user.id}
                  class="hover:brightness-110"
                  style="cursor:pointer;flex:none;background:var(--acc,#C8FF2E);border:1px solid var(--acc,#C8FF2E);color:#0A0B10;font-size:10.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:7px 15px"
                >
                  SEND REQUEST
                </span>
              </div>
            </div>

            <div
              :if={@frag? and @crew == [] and @strangers == []}
              style="padding:26px;text-align:center;font-size:12px;color:#565D73;font-weight:600"
            >
              Nobody by that name — send them an invite link instead.
            </div>
          </div>

          <%!-- right column --%>
          <div style="flex:1;min-width:min(300px,100%);display:flex;flex-direction:column;gap:16px">
            <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
              <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B;display:flex;align-items:center;justify-content:space-between">
                <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">REQUESTS</span>
                <span
                  :if={@requests != []}
                  style="background:var(--acc,#C8FF2E);color:#0A0B10;font-size:10px;font-weight:900;border-radius:999px;padding:2px 8px"
                >
                  {length(@requests)}
                </span>
              </div>
              <div
                :for={r <- @requests}
                style="display:flex;align-items:center;gap:11px;padding:11px 16px;border-bottom:1px solid #14171F"
              >
                <div style={"width:34px;height:34px;flex:none;border-radius:10px;background:#{elem(tint(r.requester.username), 0)};display:flex;align-items:center;justify-content:center;font-weight:800;font-size:12px;color:#{elem(tint(r.requester.username), 1)}"}>
                  {initial(r.requester.username)}
                </div>
                <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                  <span style="font-weight:800;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{r.requester.username}</span>
                  <span style="font-size:10px;font-weight:800;color:#22E5FF">WANTS IN</span>
                </div>
                <div style="display:flex;gap:6px;flex:none">
                  <span
                    phx-click="request-accept"
                    phx-value-id={r.id}
                    class="hover:brightness-110"
                    style="cursor:pointer;background:var(--acc,#C8FF2E);color:#0A0B10;font-size:10px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:6px 12px"
                  >
                    ACCEPT
                  </span>
                  <span
                    phx-click="request-decline"
                    phx-value-id={r.id}
                    class="hover:border-[#FF4557] hover:text-[#FF4557]"
                    style="cursor:pointer;border:1px solid #252A3A;color:#8B91A7;font-size:10px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:6px 12px"
                  >
                    DECLINE
                  </span>
                </div>
              </div>
              <div :if={@requests == []} style="padding:20px 16px;text-align:center;font-size:11.5px;color:#565D73;font-weight:600">
                No requests — quiet inbox, loud scoreboard.
              </div>
            </div>

            <div style="border-radius:16px;border:1px solid #252A3A;background:#12141D;overflow:hidden">
              <div style="padding:13px 16px;border-bottom:1px solid #1A1E2B">
                <span style="font-size:10.5px;font-weight:900;letter-spacing:1.5px;color:#565D73">GROUPS</span>
              </div>
              <div
                :for={g <- @groups}
                style={"display:flex;align-items:center;gap:11px;padding:11px 16px;border-bottom:1px solid #14171F;background:#{if @edit == g.id, do: "rgba(124,92,255,.08)", else: "transparent"}"}
              >
                <span style="width:14px;height:14px;flex:none;background:#7C5CFF;-webkit-mask:url('/icons/people.svg') center/contain no-repeat;mask:url('/icons/people.svg') center/contain no-repeat">
                </span>
                <div style="display:flex;flex-direction:column;min-width:0;flex:1">
                  <span style="font-weight:800;font-size:13px">{g.name}</span>
                  <span style="font-size:10px;color:#565D73;font-weight:700">
                    {length(g.member_ids)} {if length(g.member_ids) == 1, do: "member", else: "members"}
                  </span>
                </div>
                <span
                  phx-click="edit-group"
                  phx-value-id={g.id}
                  class="hover:border-[#7C5CFF] hover:text-[#A794FF]"
                  style={"cursor:pointer;flex:none;border:1px solid #{if @edit == g.id, do: "#7C5CFF", else: "#252A3A"};color:#{if @edit == g.id, do: "#A794FF", else: "#8B91A7"};font-size:9.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:5px 12px"}
                >
                  {if @edit == g.id, do: "EDITING…", else: "EDIT"}
                </span>
              </div>
              <form phx-submit="create-group" style="display:flex;gap:8px;padding:12px 16px">
                <input
                  type="text"
                  name="name"
                  id={"new-group-#{length(@groups)}"}
                  value=""
                  maxlength="20"
                  autocomplete="off"
                  placeholder="New group name…"
                  style="flex:1;min-width:0;background:#0D0F16;border:1px solid #252A3A;border-radius:999px;padding:9px 14px;color:#F4F5F7;font-family:'Archivo',sans-serif;font-size:12px;outline:none"
                />
                <button
                  type="submit"
                  class="hover:bg-[#1d1930]"
                  style="cursor:pointer;flex:none;background:transparent;border:1px solid #7C5CFF;color:#A794FF;font-size:10.5px;font-weight:900;letter-spacing:.5px;border-radius:999px;padding:9px 15px;align-self:center"
                >
                  + CREATE
                </button>
              </form>
              <div style="padding:0 16px 13px">
                <span style="font-size:10px;color:#565D73;font-weight:600">Groups are private — only you see the names.</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.shell>
    """
  end
end
