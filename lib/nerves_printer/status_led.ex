defmodule NervesPrinter.StatusLed do
  @moduledoc """
  Shows connection status on the Pi's ACT LED.

  * Fast blink: not on WiFi
  * Slow blink: on WiFi, searching for the PrinterRelay server
  * Solid: on WiFi and connected to the server (or on WiFi with no server configured)

  Blinking uses the kernel's LED timer trigger, so no process toggles the LED.
  """
  use GenServer

  require Logger

  @default_led_path "/sys/class/leds/ACT"
  @wifi_property ["interface", "wlan0", "connection"]
  @connected_wifi [:lan, :internet]
  @relay_event [:printer_relay, :client, :connection]
  @blink_ms %{slow: 1_000, fast: 100}

  @type pattern :: :solid | :slow | :fast

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Picks the LED pattern for the current WiFi and server state.
  """
  @spec pattern(boolean(), boolean(), :connected | :disconnected) :: pattern()
  def pattern(false = _wifi?, _relay?, _relay_status), do: :fast
  def pattern(true, true, status) when status != :connected, do: :slow
  def pattern(true, _relay?, _relay_status), do: :solid

  @doc false
  def handle_relay_event(@relay_event, _measurements, %{status: status}, pid) do
    send(pid, {:relay_connection, status})
  end

  @impl GenServer
  def init(opts) do
    handler_id = {__MODULE__, self()}
    :ok = :telemetry.attach(handler_id, @relay_event, &__MODULE__.handle_relay_event/4, self())

    subscribe_wifi = Keyword.get(opts, :subscribe_wifi, &subscribe_vintage_net/0)

    state =
      %{
        led_path: Keyword.get(opts, :led_path, @default_led_path),
        relay?: Keyword.fetch!(opts, :relay?),
        handler_id: handler_id,
        wifi?: subscribe_wifi.(),
        relay_status: :disconnected,
        pattern: nil
      }
      |> show()

    {:ok, state}
  end

  @impl GenServer
  def handle_info({VintageNet, @wifi_property, _old, connection, _meta}, state) do
    {:noreply, show(%{state | wifi?: connection in @connected_wifi})}
  end

  def handle_info({:relay_connection, status}, state) do
    {:noreply, show(%{state | relay_status: status})}
  end

  @impl GenServer
  def terminate(_reason, state), do: :telemetry.detach(state.handler_id)

  defp show(state) do
    pattern = pattern(state.wifi?, state.relay?, state.relay_status)

    if pattern != state.pattern do
      case write_pattern(state.led_path, pattern) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("StatusLed: can't set #{pattern}: #{inspect(reason)}")
      end
    end

    %{state | pattern: pattern}
  end

  defp write_pattern(path, :solid) do
    with :ok <- write(path, "trigger", "none") do
      write(path, "brightness", "1")
    end
  end

  # Setting the timer trigger creates delay_on and delay_off.
  defp write_pattern(path, blink) do
    ms = Integer.to_string(Map.fetch!(@blink_ms, blink))

    with :ok <- write(path, "trigger", "timer"),
         :ok <- write(path, "delay_on", ms) do
      write(path, "delay_off", ms)
    end
  end

  defp write(path, file, value), do: File.write(Path.join(path, file), value)

  # VintageNet only exists on the device, so it's called dynamically.
  defp subscribe_vintage_net do
    apply(VintageNet, :subscribe, [@wifi_property])
    apply(VintageNet, :get, [@wifi_property]) in @connected_wifi
  end
end
