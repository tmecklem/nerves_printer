defmodule NervesPrinter.Printer do
  @moduledoc """
  Owns the USB printer device node and writes ZPL jobs to it.

  `NervesPrinter.PrinterWatcher` calls `attached/1` and `detached/1` as the
  device node comes and goes. Jobs sent while the printer is detached are
  rejected with `{:error, :offline}` so the server can retry them.

  Processes that call `subscribe/1` receive `{:printer_status, status}` on
  every change.
  """
  use GenServer

  require Logger

  @default_device_path "/dev/usb/lp0"
  @default_id_path "/sys/class/usbmisc/lp0/device/ieee1284_id"
  @print_timeout 60_000

  @type status :: %{online: boolean(), model: String.t() | nil}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Default device node, overridable with `config :nerves_printer, device_path: ...`."
  def device_path, do: Application.get_env(:nerves_printer, :device_path, @default_device_path)

  @spec print(GenServer.server(), iodata()) :: :ok | {:error, term()}
  def print(server \\ __MODULE__, zpl), do: GenServer.call(server, {:print, zpl}, @print_timeout)

  @spec status(GenServer.server()) :: status()
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "Subscribes the caller to `{:printer_status, status}` messages. Returns the current status."
  @spec subscribe(GenServer.server()) :: status()
  def subscribe(server \\ __MODULE__), do: GenServer.call(server, :subscribe)

  def attached(server \\ __MODULE__), do: GenServer.cast(server, :attached)
  def detached(server \\ __MODULE__), do: GenServer.cast(server, :detached)

  @doc """
  Extracts the model from an IEEE 1284 device ID string.

      iex> NervesPrinter.Printer.parse_model("MFG:Zebra Technologies;CMD:EPL,ZPL;MDL:ZP 505;")
      "ZP 505"

      iex> NervesPrinter.Printer.parse_model("MFG:Zebra Technologies;")
      nil
  """
  @spec parse_model(String.t()) :: String.t() | nil
  def parse_model(ieee1284_id) do
    ieee1284_id
    |> String.split(";", trim: true)
    |> Enum.find_value(fn field ->
      case String.split(field, ":", parts: 2) do
        [key, value] when key in ["MDL", "MODEL"] -> String.trim(value)
        _ -> nil
      end
    end)
  end

  @impl GenServer
  def init(opts) do
    state = %{
      device_path: Keyword.get(opts, :device_path, device_path()),
      id_path: Keyword.get(opts, :id_path, @default_id_path),
      online: false,
      model: nil,
      subscribers: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:print, _zpl}, _from, %{online: false} = state) do
    {:reply, {:error, :offline}, state}
  end

  def handle_call({:print, zpl}, _from, state) do
    result =
      with {:ok, device} <- File.open(state.device_path, [:write, :binary]) do
        try do
          IO.binwrite(device, zpl)
        after
          File.close(device)
        end
      end

    if result != :ok, do: Logger.warning("Print failed: #{inspect(result)}")
    {:reply, result, state}
  end

  def handle_call(:status, _from, state), do: {:reply, public_status(state), state}

  def handle_call(:subscribe, {pid, _tag}, state) do
    subscribers =
      if Map.has_key?(state.subscribers, pid),
        do: state.subscribers,
        else: Map.put(state.subscribers, pid, Process.monitor(pid))

    {:reply, public_status(state), %{state | subscribers: subscribers}}
  end

  @impl GenServer
  def handle_cast(:attached, state) do
    model =
      case File.read(state.id_path) do
        {:ok, id} -> parse_model(id)
        {:error, _} -> nil
      end

    Logger.info("Printer attached: #{model || "unknown model"}")
    {:noreply, notify(%{state | online: true, model: model})}
  end

  def handle_cast(:detached, state) do
    Logger.info("Printer detached")
    {:noreply, notify(%{state | online: false, model: nil})}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  defp public_status(state), do: %{online: state.online, model: state.model}

  defp notify(state) do
    status = public_status(state)
    Enum.each(Map.keys(state.subscribers), &send(&1, {:printer_status, status}))
    state
  end
end
