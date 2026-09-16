if Code.ensure_loaded?(Phoenix.Tracker) do
  defmodule PrinterRelay do
    @moduledoc """
    Send ZPL from a Phoenix app to label printers connected over Phoenix Channels.

    Printers connect with `PrinterRelay.Client` to a socket defined with
    `use PrinterRelay.Socket`. Add `PrinterRelay` to your supervision tree after
    your PubSub:

        children = [
          {Phoenix.PubSub, name: MyApp.PubSub},
          {PrinterRelay, pubsub: MyApp.PubSub},
          MyAppWeb.Endpoint
        ]

    Then print to any connected printer from any node in the cluster:

        PrinterRelay.print("shop-1", "^XA^FDHello^FS^XZ")
    """

    alias PrinterRelay.Tracker

    @default_timeout 15_000

    @type printer :: %{
            id: String.t(),
            online: boolean(),
            model: String.t() | nil,
            client_version: String.t() | nil,
            connected_at: integer()
          }

    @type print_error ::
            :not_connected | :offline | :timeout | :disconnected | {:printer, String.t()}

    @doc """
    Starts the printer presence tracker.

    ## Options

      * `:pubsub` - the `Phoenix.PubSub` server name (required)
    """
    def child_spec(opts) do
      %{
        id: __MODULE__,
        start: {Tracker, :start_link, [Keyword.fetch!(opts, :pubsub)]},
        type: :supervisor
      }
    end

    @doc """
    Prints `zpl` on the printer with `printer_id` and waits for the result.

    Printing is at most once: a job that times out or loses its connection is
    not retried, because it may already have printed.

    ## Options

      * `:timeout` - milliseconds to wait for the printer (default #{@default_timeout})
    """
    @spec print(String.t(), iodata(), keyword()) :: :ok | {:error, print_error()}
    def print(printer_id, zpl, opts \\ []) do
      timeout = Keyword.get(opts, :timeout, @default_timeout)

      case Tracker.lookup(printer_id) do
        nil -> {:error, :not_connected}
        %{online: false} -> {:error, :offline}
        %{pid: pid} -> send_job(pid, IO.iodata_to_binary(zpl), timeout)
      end
    end

    @doc "Lists connected printers, oldest connection first."
    @spec printers() :: [printer()]
    def printers, do: Tracker.printers()

    @doc """
    Subscribes the caller to `{:printer_relay, :printers_changed}` messages,
    sent whenever a printer connects, disconnects, or changes status on any node.
    """
    @spec subscribe() :: :ok | {:error, term()}
    def subscribe, do: Tracker.subscribe()

    # The monitor doubles as a process alias, so replies that arrive after a
    # timeout are dropped instead of landing in the caller's mailbox.
    defp send_job(pid, zpl, timeout) do
      ref = :erlang.monitor(:process, pid, alias: :demonitor)
      send(pid, {:printer_relay_print, ref, zpl})

      receive do
        {^ref, result} ->
          result

        {:DOWN, ^ref, :process, _pid, _reason} ->
          {:error, :disconnected}
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          {:error, :timeout}
      end
    end
  end
end
