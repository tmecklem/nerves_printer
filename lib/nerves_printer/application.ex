defmodule NervesPrinter.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  # Mix isn't available at runtime on the device.
  @target Mix.target()

  @impl true
  def start(_type, _args) do
    relay_config = Application.get_env(:nerves_printer, PrinterRelay.Client, [])

    # The LED starts before the relay client so it sees the first join.
    children =
      [
        NervesPrinter.Printer,
        NervesPrinter.PrinterWatcher
      ] ++
        status_led_children(@target, relay_config) ++
        relay_children(relay_config)

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesPrinter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  The status LED child, started only on the device.
  """
  def status_led_children(:host, _relay_config), do: []

  def status_led_children(_target, relay_config) do
    [{NervesPrinter.StatusLed, relay?: relay_config[:uri] != nil}]
  end

  @doc """
  The relay client child, started only when a server URI is configured.
  """
  def relay_children(config) do
    if config[:uri] do
      opts =
        config
        |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
        |> Keyword.put_new_lazy(:printer_id, &Nerves.Runtime.serial_number/0)
        |> Keyword.put(:backend, {NervesPrinter.Printer, NervesPrinter.Printer})

      [{PrinterRelay.Client, opts}]
    else
      []
    end
  end
end
