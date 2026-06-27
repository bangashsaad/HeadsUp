defmodule HeadsUpWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by channel tests.

  Such tests rely on `Phoenix.ChannelTest` and import other functionality
  to make it easier to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import HeadsUpWeb.ChannelCase

      # The default endpoint for testing
      @endpoint HeadsUpWeb.Endpoint
    end
  end

  setup tags do
    HeadsUp.DataCase.setup_sandbox(tags)
    :ok
  end
end
