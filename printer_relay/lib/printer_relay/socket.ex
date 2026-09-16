if Code.ensure_loaded?(Phoenix.Socket) do
  defmodule PrinterRelay.Socket do
    @moduledoc """
    Defines the socket printers connect to.

        defmodule MyAppWeb.PrinterSocket do
          use PrinterRelay.Socket

          @impl PrinterRelay.Socket
          def authenticate(token, _connect_info) do
            case MyApp.Printers.verify_token(token) do
              {:ok, printer_id} -> {:ok, printer_id}
              _ -> :error
            end
          end
        end

    Mount it in your endpoint:

        socket "/printer_relay", MyAppWeb.PrinterSocket, websocket: true, longpoll: false

    A printer may only join the channel for the printer id its token returns.
    """

    @doc """
    Verifies the token a printer connects with and returns its printer id.
    """
    @callback authenticate(token :: String.t(), connect_info :: map()) ::
                {:ok, String.t()} | :error

    defmacro __using__(_opts) do
      quote do
        use Phoenix.Socket
        @behaviour PrinterRelay.Socket

        channel("printer_relay:printer:*", PrinterRelay.PrinterChannel)

        @impl Phoenix.Socket
        def connect(params, socket, connect_info) do
          PrinterRelay.Socket.__connect__(__MODULE__, params, socket, connect_info)
        end

        @impl Phoenix.Socket
        def id(socket), do: "printer_relay_socket:" <> socket.assigns.printer_relay_id
      end
    end

    @doc false
    def __connect__(module, %{"token" => token}, socket, connect_info) when is_binary(token) do
      case module.authenticate(token, connect_info) do
        {:ok, printer_id} when is_binary(printer_id) ->
          {:ok, Phoenix.Socket.assign(socket, :printer_relay_id, printer_id)}

        _ ->
          :error
      end
    end

    def __connect__(_module, _params, _socket, _connect_info), do: :error
  end
end
