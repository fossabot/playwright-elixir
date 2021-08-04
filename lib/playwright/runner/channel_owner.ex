defmodule Playwright.Runner.ChannelOwner do
  @moduledoc false
  @base [:connection, :guid, :initializer, :parent, :type, :listeners]

  require Logger

  defmacro __using__(config \\ []) do
    extra =
      case config do
        [fields: fields] ->
          fields

        _ ->
          []
      end

    fields = extra ++ @base

    quote do
      @derive {Inspect, only: [:guid, :initializer] ++ unquote(extra)}

      alias Playwright.Extra
      alias Playwright.Runner.Channel
      alias Playwright.Runner.Connection

      defstruct unquote(fields)

      @type t() :: %__MODULE__{}

      @doc false
      def channel_owner(
            parent,
            %{guid: guid, initializer: initializer, type: type} = args
          ) do
        base = %__MODULE__{
          connection: parent.connection,
          guid: guid,
          initializer: initializer,
          parent: parent,
          type: type,
          listeners: %{}
        }

        struct(
          base,
          Enum.into(unquote(extra), %{}, fn e ->
            {e, initializer[camelcase(e)]}
          end)
        )
      end

      # private
      # ------------------------------------------------------------------------

      defp camelcase(atom) do
        Extra.Atom.to_string(atom)
        |> Recase.to_camel()
        |> Extra.Atom.from_string()
      end
    end
  end

  @doc false
  def from(params, parent) do
    apply(module(params), :new, [parent, params])
  end

  # private
  # ------------------------------------------------------------------------

  defp module(%{type: type}) do
    String.to_existing_atom("Elixir.Playwright.#{type}")
  rescue
    ArgumentError ->
      message = "ChannelOwner of type #{inspect(type)} is not yet defined"
      Logger.debug(message)
      exit(message)
  end
end
