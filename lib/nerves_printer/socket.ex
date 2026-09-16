defmodule NervesPrinter.Socket do
  @moduledoc """
  Phoenix channel client for the Equipment Tracker server.

  Joins `printer:<printer_id>` with the printer's status, pushes `"status"`
  whenever it changes, and prints each `"print"` event:

      server -> client  "print"         %{"job_id" => id, "zpl" => zpl}
      client -> server  "print_result"  %{"job_id" => id, "ok" => true}
                                        %{"job_id" => id, "ok" => false, "error" => reason}

  Configure with:

      config :nerves_printer, NervesPrinter.Socket,
        uri: "wss://example.com/printer/websocket",
        printer_id: "shop-1"

  `printer_id` defaults to the device serial number.
  """
  use Slipstream, restart: :permanent

  require Logger

  alias NervesPrinter.Printer

  def start_link(opts) do
    Slipstream.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Slipstream
  def init(opts) do
    {printer, opts} = Keyword.pop(opts, :printer, Printer)
    {printer_id, opts} = Keyword.pop_lazy(opts, :printer_id, &Nerves.Runtime.serial_number/0)
    opts = Keyword.drop(opts, [:name])

    status = Printer.subscribe(printer)

    socket =
      new_socket()
      |> assign(printer: printer, topic: "printer:#{printer_id}", status: status)
      |> connect!(opts)

    {:ok, socket}
  end

  @impl Slipstream
  def handle_connect(socket) do
    {:ok, join(socket, socket.assigns.topic, status_payload(socket.assigns.status))}
  end

  @impl Slipstream
  def handle_join(topic, _response, socket) do
    Logger.info("Joined #{topic}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_message(topic, "print", %{"job_id" => job_id, "zpl" => zpl}, socket) do
    result =
      case Printer.print(socket.assigns.printer, zpl) do
        :ok -> %{"job_id" => job_id, "ok" => true}
        {:error, reason} -> %{"job_id" => job_id, "ok" => false, "error" => inspect(reason)}
      end

    push(socket, topic, "print_result", result)
    {:ok, socket}
  end

  def handle_message(topic, event, payload, socket) do
    Logger.warning("Ignoring #{event} on #{topic}: #{inspect(payload)}")
    {:ok, socket}
  end

  @impl Slipstream
  def handle_info({:printer_status, status}, socket) do
    socket = assign(socket, :status, status)
    topic = socket.assigns.topic

    # Rejoins send fresh status in their params, so only push while joined.
    if joined?(socket, topic), do: push(socket, topic, "status", status_payload(status))

    {:noreply, socket}
  end

  @impl Slipstream
  def handle_topic_close(topic, _reason, socket) do
    rejoin(socket, topic, status_payload(socket.assigns.status))
  end

  defp status_payload(status), do: %{"online" => status.online, "model" => status.model}
end
