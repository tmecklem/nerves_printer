defmodule NervesPrinter.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        NervesPrinter.Printer,
        NervesPrinter.PrinterWatcher
      ] ++ relay_children(Application.get_env(:nerves_printer, PrinterRelay.Client, []))

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesPrinter.Supervisor]
    Supervisor.start_link(children, opts)
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
