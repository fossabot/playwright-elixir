defmodule Playwright.Runner.Channel.Callback do
  @moduledoc false
  require Logger
  alias Playwright.Runner.Channel.Error
  alias Playwright.Runner.Channel.Response

  defstruct [:listener, :message]

  def new(listener, message) do
    %__MODULE__{
      listener: listener,
      message: message
    }
  end

  def resolve(%{listener: listener}, %Error{} = error) do
    GenServer.reply(listener, error)
  end

  def resolve(%{listener: listener}, %Response{} = response) do
    Logger.debug("Callback.resolve w/ response: #{inspect(response)}")
    GenServer.reply(listener, response.parsed)
  end
end
