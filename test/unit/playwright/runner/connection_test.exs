defmodule Playwright.Runner.ConnectionTest do
  use ExUnit.Case
  alias Playwright.Runner.Catalog
  alias Playwright.Runner.Channel
  alias Playwright.Runner.Connection
  alias Playwright.Runner.ConnectionTest.TestTransport

  setup do
    %{
      connection: start_supervised!({Connection, {TestTransport, ["param"]}})
    }
  end

  describe "get/2" do
    test "always finds the `Root` resource", %{connection: connection} do
      Connection.get(connection, {:guid, "Root"})
      |> assert()
    end
  end

  describe "post/2" do
    @tag :skip # flaky. worth investigating to determine if there's a real issue here.
    test "creating a new item", %{connection: connection} do
      cmd = Channel.Command.new("Browser", "newContext", %{headless: false})

      Task.start(fn ->
        :timer.sleep(10)

        Connection.recv(
          connection,
          {:text,
           Jason.encode!(%{
             guid: "",
             method: "__create__",
             params: %{
               guid: "context@1",
               initializer: %{},
               type: "BrowserContext"
             }
           })}
        )
      end)

      Task.start(fn ->
        :timer.sleep(20)

        Connection.recv(
          connection,
          {:text,
           Jason.encode!(%{
             id: 1,
             result: %{
               context: %{guid: "context@1"}
             }
           })}
        )
      end)

      result = Connection.post(connection, cmd)
      assert result.guid == "context@1"
    end

    test "removing an item via __dispose__ also removes its 'children'", %{connection: connection} do
      %{catalog: catalog} = :sys.get_state(connection)
      # root = catalog["Root"]
      root = Catalog.get(catalog, "Root")
      json = Jason.encode!(%{guid: "browser@1", method: "__dispose__"})

      catalog =
        catalog
        |> Catalog.put("browser@1", %{guid: "browser@1", parent: %{guid: "Root"}, type: "Browser"})
        |> Catalog.put("context@1", %{guid: "context@1", parent: %{guid: "browser@1"}, type: "BrowserContext"})
        |> Catalog.put("page@1", %{guid: "page@1", parent: %{guid: "context@1"}, type: "Page"})

      :sys.replace_state(connection, fn state -> %{state | catalog: catalog} end)

      Connection.get(connection, %{guid: "browser@1"}, nil)
      |> assert()

      Connection.get(connection, %{guid: "context@1"}, nil)
      |> assert()

      Connection.get(connection, %{guid: "page@1"}, nil)
      |> assert()

      Connection.recv(connection, {:text, json})

      Connection.get(connection, %{guid: "browser@1"}, nil)
      |> refute()

      Connection.get(connection, %{guid: "context@1"}, nil)
      |> refute()

      Connection.get(connection, %{guid: "page@1"}, nil)
      |> refute()

      %{catalog: catalog} = :sys.get_state(connection)
      assert catalog.dictionary == %{"Root" => root}
    end
  end

  describe "recv/2 with a `__create__` payload" do
    test "adds the item to the catalog", %{connection: connection} do
      json =
        Jason.encode!(%{
          guid: "",
          method: "__create__",
          params: %{
            guid: "page@1",
            initializer: %{},
            type: "Page"
          }
        })

      Connection.recv(connection, {:text, json})

      assert Connection.get(connection, {:guid, "page@1"}).type == "Page"
    end
  end

  # @impl
  # ----------------------------------------------------------------------------

  describe "@impl: init/1" do
    test "starts the `Transport`, with provided configuration", %{connection: connection} do
      %{transport: transport} = :sys.get_state(connection)
      assert Process.alive?(transport.pid)
    end
  end

  describe "@impl: handle_call/3 for :get" do
    # test "when the desired item is in the catalog, returns that and does not record the query", %{
    #   connection: connection
    # } do
    #   state = :sys.get_state(connection)
    #   {response, result, %{queries: queries}} = Connection.handle_call({:get, {:guid, "Root"}}, :caller, state)

    #   assert response == :reply
    #   assert result.type == "Root"
    #   assert queries == %{}
    # end

    # test "when the desired item is NOT in the catalog, records the query and does not reply", %{connection: connection} do
    #   state = :sys.get_state(connection)
    #   {response, %{queries: queries}} = Connection.handle_call({:get, {:guid, "Missing"}}, :caller, state)

    #   assert response == :noreply
    #   assert queries == %{"Missing" => :caller}
    # end
  end

  describe "@impl: handle_call/3 for :post" do
    test "sends a message and blocks on a matching return message", %{connection: connection} do
      state = %{:sys.get_state(connection) | messages: %{pending: %{}}}

      from = {self(), :tag}
      cmd = Channel.Command.new("page@1", "click", %{selector: "a.link"})
      cid = cmd.id

      {response, state} = Connection.handle_call({:post, {:cmd, cmd}}, from, state)
      assert response == :noreply
      assert state.messages == %{pending: %{cid => cmd}}
      assert state.queries == %{cid => from}

      posted = TestTransport.dump(state.transport.pid)
      assert posted == [Jason.encode!(cmd)]

      {_, %{messages: messages, queries: queries}} =
        Connection.handle_cast({:recv, {:text, Jason.encode!(%{id: cid})}}, state)

      assert messages.pending == %{}
      assert queries == %{}

      assert_received(
        {:tag,
         %{
           id: ^cid,
           guid: "page@1",
           method: "click",
           params: %{selector: "a.link"}
         }}
      )
    end
  end

  # describe "@impl: handle_cast/2 for :recv" do
  #   test "sends a reply to an awaiting query", %{connection: connection} do
  #     state = :sys.get_state(connection)

  #     from = {self(), :tag}

  #     json =
  #       Jason.encode!(%{
  #         guid: "",
  #         method: "__create__",
  #         params: %{
  #           guid: "Playwright",
  #           type: "Playwright",
  #           initializer: "definition"
  #         }
  #       })

  #     {_, %{queries: queries} = state} = Connection.handle_call({:get, {:guid, "Playwright"}}, from, state)
  #     assert queries == %{"Playwright" => from}

  #     Connection.handle_cast({:recv, {:text, json}}, state)
  #     assert_received({:tag, %Playwright.Playwright{}})
  #   end
  # end

  # helpers
  # ----------------------------------------------------------------------------

  defmodule TestTransport do
    use GenServer

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    def start_link!(config) do
      {:ok, pid} = start_link(config)
      pid
    end

    def dump(pid) do
      GenServer.call(pid, :dump)
    end

    def post(pid, message) do
      GenServer.cast(pid, {:post, message})
    end

    # ---

    def init([connection | args]) do
      {
        :ok,
        %{
          connection: connection,
          args: args,
          posted: []
        }
      }
    end

    def handle_call(:dump, _from, %{posted: posted} = state) do
      {:reply, posted, state}
    end

    def handle_cast({:post, message}, %{posted: posted} = state) do
      {:noreply, %{state | posted: posted ++ [message]}}
    end
  end
end
