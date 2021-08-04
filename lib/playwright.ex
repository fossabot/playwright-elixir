defmodule Playwright do
  @moduledoc false
  use Application

  @doc false
  @impl Application
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, strategy: :one_for_one, name: Playwright.BrowserType.Supervisor}
    ]

    options = [
      name: Playwright.Supervisor,
      strategy: :one_for_one
    ]

    Supervisor.start_link(children, options)
  end
end
