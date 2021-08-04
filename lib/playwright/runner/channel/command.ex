defmodule Playwright.Runner.Channel.Command do
  @moduledoc false
  # `Command` represents an imperative sent to the Playwright server.
  # The `id` is used to match reponses and reply to the caller with a `Response`.

  alias Playwright.Runner.Channel.Command

  @enforce_keys [:guid, :id, :method, :params]

  @derive [Jason.Encoder]
  defstruct [
    :guid,
    :id,
    :method,
    :params
  ]

  @type t() :: %__MODULE__{
          guid: binary(),
          id: integer(),
          method: binary(),
          params: map()
        }

  # Creates a new `Command` struct. A monotonically-incremented `id` is added.
  # This `id` is used to match `Response` messages to the `Command`. `params`
  # are optional here and are passed to the Playwright server. They may actually
  # be required for the server-side `method` to make sense.
  def new(guid, method, params \\ %{}) do
    %Command{
      guid: guid,
      id: System.unique_integer([:monotonic, :positive]),
      method: method,
      params: params
    }
  end
end
