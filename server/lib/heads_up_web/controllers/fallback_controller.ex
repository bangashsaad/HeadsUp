defmodule HeadsUpWeb.FallbackController do
  @moduledoc """
  Translates controller `{:error, ...}` results into JSON responses.
  """
  use HeadsUpWeb, :controller

  # Validation errors (e.g. invalid signup)
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: HeadsUpWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  # Not found
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: HeadsUpWeb.ErrorJSON)
    |> render(:"404")
  end

  # A simple message-based error, e.g. {:error, "Invalid email or password"}
  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: message}})
  end

  # Named domain errors, e.g. {:error, :not_enough_players}
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: %{detail: reason |> to_string() |> String.replace("_", " ")}})
  end
end
