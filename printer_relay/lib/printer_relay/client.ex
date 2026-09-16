if Code.ensure_loaded?(Slipstream) do
  defmodule PrinterRelay.Client do
    @moduledoc """
    Connects a printer to a Phoenix app running `PrinterRelay`.

        children = [
          {PrinterRelay.Client,
           uri: "wss://example.com/printer_relay/websocket",
           token: "...",
           printer_id: "shop-1",
           backend: {MyPrinterBackend, []}}
        ]

    `backend` implements `PrinterRelay.Client.Backend`. Any other options are
    passed to `Slipstream.connect/2`. The client reconnects and rejoins with
    backoff when the connection drops.
    """
    use Slipstream, restart: :permanent

    require Logger

    @protocol 1
    @client_opts [:name, :token, :printer_id, :backend]

    def start_link(opts) do
      Slipstream.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
    end

    @doc false
    def connect_uri(uri, token) do
      uri = URI.parse(uri)
      token_query = URI.encode_query(%{"token" => token})
      query = if uri.query in [nil, ""], do: token_query, else: uri.query <> "&" <> token_query
      URI.to_string(%{uri | query: query})
    end

    @impl Slipstream
    def init(opts) do
      {backend_module, backend_arg} = backend = Keyword.fetch!(opts, :backend)
      printer_id = Keyword.fetch!(opts, :printer_id)

      connect_opts =
        opts
        |> Keyword.drop(@client_opts)
        |> Keyword.update!(:uri, &connect_uri(&1, Keyword.fetch!(opts, :token)))

      socket =
        new_socket()
        |> assign(
          backend: backend,
          topic: "printer_relay:printer:" <> printer_id,
          status: backend_module.subscribe(backend_arg)
        )
        |> connect!(connect_opts)

      {:ok, socket}
    end

    @impl Slipstream
    def handle_connect(socket) do
      %{topic: topic, status: status} = socket.assigns

      case rejoin(socket, topic, join_params(status)) do
        {:ok, socket} -> {:ok, socket}
        {:error, :never_joined} -> {:ok, join(socket, topic, join_params(status))}
      end
    end

    @impl Slipstream
    def handle_join(topic, _response, socket) do
      Logger.info("PrinterRelay: joined #{topic}")
      {:ok, socket}
    end

    @impl Slipstream
    def handle_message(topic, "print", %{"job_id" => job_id, "zpl" => zpl}, socket) do
      {module, arg} = socket.assigns.backend

      result =
        case module.print(arg, zpl) do
          :ok -> %{"job_id" => job_id, "ok" => true}
          {:error, reason} -> %{"job_id" => job_id, "ok" => false, "error" => inspect(reason)}
        end

      _ = push(socket, topic, "print_result", result)
      {:ok, socket}
    end

    def handle_message(topic, event, _payload, socket) do
      Logger.warning("PrinterRelay: ignoring #{inspect(event)} on #{topic}")
      {:ok, socket}
    end

    @impl Slipstream
    def handle_info({:printer_relay_status, status}, socket) do
      socket = assign(socket, :status, status)
      topic = socket.assigns.topic

      # A rejoin sends the latest status in its params, so only push while joined.
      if joined?(socket, topic), do: push(socket, topic, "status", status_params(status))

      {:noreply, socket}
    end

    @impl Slipstream
    def handle_topic_close(topic, reason, socket) do
      Logger.warning("PrinterRelay: #{topic} closed: #{inspect(reason)}")
      rejoin(socket, topic, join_params(socket.assigns.status))
    end

    @impl Slipstream
    def handle_disconnect({:error, {:upgrade_failure, %{status_code: 403}}}, socket) do
      Logger.error("PrinterRelay: server rejected the connection (HTTP 403); check the token")
      reconnect(socket)
    end

    def handle_disconnect(reason, socket) do
      Logger.warning("PrinterRelay: disconnected: #{inspect(reason)}")
      reconnect(socket)
    end

    defp join_params(status) do
      status
      |> status_params()
      |> Map.merge(%{
        "protocol" => @protocol,
        "client_version" => to_string(Application.spec(:printer_relay, :vsn))
      })
    end

    defp status_params(status), do: %{"online" => status.online, "model" => status.model}
  end
end
