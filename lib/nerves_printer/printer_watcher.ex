defmodule NervesPrinter.PrinterWatcher do
  @moduledoc """
  Polls for the printer device node and tells `NervesPrinter.Printer` when it
  appears or disappears.

  Polling is used instead of uevents so the same code runs on the host in tests.
  """
  use GenServer

  @default_interval 1_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl GenServer
  def init(opts) do
    state = %{
      printer: Keyword.get(opts, :printer, NervesPrinter.Printer),
      device_path: Keyword.get(opts, :device_path, NervesPrinter.Printer.device_path()),
      interval: Keyword.get(opts, :interval, @default_interval),
      present?: false
    }

    {:ok, check(state)}
  end

  @impl GenServer
  def handle_info(:check, state), do: {:noreply, check(state)}

  defp check(state) do
    present? = File.exists?(state.device_path)

    cond do
      present? and not state.present? -> NervesPrinter.Printer.attached(state.printer)
      state.present? and not present? -> NervesPrinter.Printer.detached(state.printer)
      true -> :ok
    end

    Process.send_after(self(), :check, state.interval)
    %{state | present?: present?}
  end
end
