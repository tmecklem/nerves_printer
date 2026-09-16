if Code.ensure_loaded?(Phoenix.Tracker) do
  defmodule PrinterRelay.TestPrinter do
    @moduledoc """
    A fake connected printer for testing apps that use `PrinterRelay`.

    It registers like a real printer, so `PrinterRelay.print/3`,
    `PrinterRelay.printers/0`, and `PrinterRelay.subscribe/0` behave as they
    would with a device connected.

        test "prints the label" do
          start_supervised!({PrinterRelay.TestPrinter, id: "shop-1", notify: self()})

          # ... exercise code that calls PrinterRelay.print("shop-1", zpl)

          assert_receive {:printer_relay_test_print, "shop-1", zpl}
        end

    ## Options

      * `:id` - the printer id (required)
      * `:notify` - a pid sent `{:printer_relay_test_print, id, zpl}` for each job
      * `:result` - what each job returns: `:ok` (default) or `{:error, reason}`
      * `:online` - whether a device is attached (default `true`)
      * `:model` - the reported model (default `"Test Printer"`)
    """
    use GenServer

    alias PrinterRelay.Tracker

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @doc "Changes whether the printer reports a device attached."
    def set_online(pid, online?), do: GenServer.call(pid, {:set_online, online?})

    @impl GenServer
    def init(opts) do
      state = %{
        id: Keyword.fetch!(opts, :id),
        notify: Keyword.get(opts, :notify),
        result: Keyword.get(opts, :result, :ok)
      }

      meta = %{
        online: Keyword.get(opts, :online, true),
        model: Keyword.get(opts, :model, "Test Printer"),
        client_version: "test"
      }

      {:ok, _ref} = Tracker.track(self(), state.id, meta)
      {:ok, state}
    end

    @impl GenServer
    def handle_call({:set_online, online?}, _from, state) do
      {:ok, _ref} = Tracker.update(self(), state.id, %{online: online?})
      {:reply, :ok, state}
    end

    @impl GenServer
    def handle_info({:printer_relay_print, reply_to, zpl}, state) do
      if state.notify, do: send(state.notify, {:printer_relay_test_print, state.id, zpl})

      result =
        case state.result do
          :ok -> :ok
          {:error, reason} -> {:error, {:printer, to_string(reason)}}
        end

      send(reply_to, {reply_to, result})
      {:noreply, state}
    end
  end
end
