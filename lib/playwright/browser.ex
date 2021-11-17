defmodule Playwright.Browser do
  @moduledoc """
  `Playwright.Browser` represents a launched web browser instance managed by
  Playwright.

  A `Playwright.Browser` is created via:

  - `Playwright.BrowserType.launch/0`, when using the "driver" transport.
  - `Playwright.BrowserType.connect/1`, when using the "websocket" transport.
  """
  use Playwright.Runner.ChannelOwner, fields: [:name, :version]
  alias Playwright.Runner.Channel
  alias Playwright.Runner.ChannelOwner

  @impl ChannelOwner
  def new(parent, %{initializer: %{version: version} = initializer} = args) do
    args = %{args | initializer: Map.put(initializer, :version, cut_version(version))}
    init(parent, args)
  end

  @doc false
  def contexts(subject) do
    Channel.all(subject.connection, %{
      parent: subject,
      type: "BrowserContext"
    })
  end

  @doc """
  Create a new BrowserContext for this Browser. A BrowserContext is somewhat
  equivalent to an "incognito" browser "window".
  """
  def new_context(%Playwright.Browser{connection: connection} = subject, options \\ %{}) do
    params =
      prepare(
        Map.merge(
          %{
            no_default_viewport: false
          },
          options
        )
      )

    context = Channel.send(subject, "newContext", params)

    case context do
      %Playwright.BrowserContext{} ->
        Channel.patch(connection, context.guid, %{browser: subject})

      _other ->
        raise("expected new_context to return a  Playwright.BrowserContext, received: #{inspect(context)}")
    end
  end

  @doc """
  Create a new Page for this Browser. A Page is somewhat equivalent to a "tab"
  in a browser "window".

  Note that `Playwright.Browser.new_page/1` will also create a new
  `Playwright.BrowserContext`. That `BrowserContext` becomes, both, the
  *parent* the `Page`, and *owned by* the `Page`. When the `Page` closes,
  the context goes with it.
  """
  @spec new_page(Playwright.Browser.t()) :: Playwright.Page.t()
  def new_page(%{connection: connection} = subject) do
    context = new_context(subject)
    page = Playwright.BrowserContext.new_page(context)

    Channel.patch(connection, context.guid, %{owner_page: page})

    case page do
      %Playwright.Page{} ->
        Channel.patch(connection, page.guid, %{owned_context: context})

      _other ->
        raise("expected new_page to return a  Playwright.Page, received: #{inspect(page)}")
    end
  end

  # private
  # ----------------------------------------------------------------------------

  # Chromium version is \d+.\d+.\d+.\d+, but that doesn't parse well with
  # `Version`. So, until it causes issue we're cutting it down to
  # <major.minor.patch>.
  defp cut_version(version) do
    version |> String.split(".") |> Enum.take(3) |> Enum.join(".")
  end

  defp prepare(%{extra_http_headers: headers}) do
    %{
      extraHTTPHeaders:
        Enum.reduce(headers, [], fn {k, v}, acc ->
          [%{name: k, value: v} | acc]
        end)
    }
  end

  defp prepare(opts) when is_map(opts) do
    Enum.reduce(opts, %{}, fn {k, v}, acc -> Map.put(acc, prepare(k), v) end)
  end

  defp prepare(atom) when is_atom(atom) do
    Extra.Atom.to_string(atom)
    |> Recase.to_camel()
    |> Extra.Atom.from_string()
  end
end
