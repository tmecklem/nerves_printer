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
      ] ++ socket_children()

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesPrinter.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # The socket only starts when a server URI is configured.
  defp socket_children do
    config = Application.get_env(:nerves_printer, NervesPrinter.Socket, [])
    if config[:uri], do: [{NervesPrinter.Socket, config}], else: []
  end
end
