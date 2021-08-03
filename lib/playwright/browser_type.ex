defmodule Playwright.BrowserType do
  @moduledoc """
  The `Playwright.BrowserType` module exposes functions that either:

  - launch a new browser instance via a `Port`
  - connect to a running playwright websocket

  ## Examples

  Open a new chromium via the CLI driver:

      {connection, browser} = Playwright.BrowserType.launch()

  Connect to a running playwright instances:

      {connection, browser} = Playwright.BrowserType.connect("ws://localhost:3000/playwright")

  """
  use Playwright.Runner.ChannelOwner

  require Logger

  alias Playwright.BrowserType
  alias Playwright.Runner.Config
  alias Playwright.Runner.Connection
  alias Playwright.Runner.Transport

  def new(parent, args) do
    channel_owner(parent, args)
  end

  @doc """
  Connect to a running playwright server.
  """
  @spec connect(binary()) :: {pid(), Playwright.Browser.t()}
  def connect(ws_endpoint) do
    with {:ok, connection} <- new_session(Transport.WebSocket, [ws_endpoint]),
         launched <- launched_browser(connection),
         browser <- Channel.get(connection, {:guid, launched}) do
      {connection, browser}
    else
      {:error, error} -> {:error, {"Error connecting to #{inspect(ws_endpoint)}", error}}
      error -> {:error, {"Error connecting to #{inspect(ws_endpoint)}", error}}
    end
  end

  @doc """
  Launch a new local browser.
  """
  @spec launch() :: {pid(), Playwright.Browser.t()}
  def launch do
    {:ok, connection} = new_session(Transport.Driver, ["assets/node_modules/playwright/lib/cli/cli.js"])
    {connection, chromium(connection)}
  end

  # private
  # ----------------------------------------------------------------------------

  defp launch(%BrowserType{} = subject) do
    browser = Channel.send(subject, "launch", Config.launch_options(true))

    case browser do
      %Playwright.Browser{} ->
        browser

      _other ->
        raise("expected launch to return a  Playwright.Browser, received: #{inspect(browser)}")
    end
  end

  defp chromium(connection) do
    playwright = Channel.get(connection, {:guid, "Playwright"})

    case playwright do
      %Playwright.Playwright{} ->
        %{guid: guid} = playwright.initializer.chromium

        Channel.get(connection, {:guid, guid}) |> launch()

      _other ->
        raise("expected chromium to return a  Playwright.Playwright, received: #{inspect(playwright)}")
    end
  end

  defp new_session(transport, args) do
    DynamicSupervisor.start_child(
      BrowserType.Supervisor,
      {Connection, {transport, args}}
    )
  end

  defp launched_browser(connection) do
    playwright = Channel.get(connection, {:guid, "Playwright"})
    %{guid: guid} = playwright.initializer.preLaunchedBrowser
    guid
  end
end
