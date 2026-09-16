# PrinterRelay

Send ZPL from a Phoenix app to label printers that connect to it over Phoenix
Channels. The printers can be anywhere with outbound internet access, such as a
Raspberry Pi running Nerves with a Zebra printer on its USB port.

- **Server:** a socket and channel for printers, `PrinterRelay.print/3`, and
  cluster-wide presence through `Phoenix.Tracker`
- **Client:** `PrinterRelay.Client`, a Slipstream client that prints each job
  through a backend you provide

## Installation

```elixir
def deps do
  [
    {:printer_relay, github: "tmecklem/nerves_printer", sparse: "printer_relay"}
  ]
end
```

A Phoenix app needs `:phoenix` and `:phoenix_pubsub` (already present in
Phoenix apps). A device needs `:slipstream` and, for `wss://`, `:castore`.

## Server setup

Define a socket that verifies printer tokens:

```elixir
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
```

Mount it in your endpoint:

```elixir
socket "/printer_relay", MyAppWeb.PrinterSocket, websocket: true, longpoll: false
```

Start the tracker after your PubSub:

```elixir
children = [
  {Phoenix.PubSub, name: MyApp.PubSub},
  {PrinterRelay, pubsub: MyApp.PubSub},
  MyAppWeb.Endpoint
]
```

Print:

```elixir
PrinterRelay.print("shop-1", "^XA^FO50,50^A0N,50,50^FDHello^FS^XZ")
#=> :ok
#=> {:error, :not_connected | :offline | :timeout | :disconnected | {:printer, reason}}
```

List printers, or get notified when they change (for example in a LiveView):

```elixir
PrinterRelay.printers()
#=> [%{id: "shop-1", online: true, model: "ZP 505", client_version: "0.1.0", connected_at: ...}]

PrinterRelay.subscribe()
# receive {:printer_relay, :printers_changed}
```

## Client setup

Implement `PrinterRelay.Client.Backend` for your printer and start the client:

```elixir
children = [
  {PrinterRelay.Client,
   uri: "wss://example.com/printer_relay/websocket",
   token: "...",
   printer_id: "shop-1",
   backend: {MyPrinter, MyPrinter}}
]
```

The client reconnects and rejoins with backoff, and sends status changes
reported by the backend.

## Testing your app

`PrinterRelay.TestPrinter` registers a fake printer, so code that calls
`PrinterRelay.print/3` can be tested without sockets:

```elixir
start_supervised!({PrinterRelay.TestPrinter, id: "shop-1", notify: self()})
# ... code under test prints to "shop-1"
assert_receive {:printer_relay_test_print, "shop-1", zpl}
```

Options include `result: {:error, "out of labels"}`, `online: false`, and
`TestPrinter.set_online/2`.

## Delivery guarantees

Printing is at most once. A job that times out or loses its connection is not
retried, because it may already have printed and a duplicate label is usually
worse than a visible error.

`print/3` sends each job to a single channel process rather than broadcasting
to a topic, so a printer that briefly has two connections during a reconnect
still prints once.

## Protocol (version 1)

| Step | Direction | Message |
|---|---|---|
| Connect | printer to server | WebSocket with `token` query param; rejected with HTTP 403 unless `authenticate/2` returns `{:ok, printer_id}` |
| Join | printer to server | topic `printer_relay:printer:<printer_id>`, params `%{"protocol" => 1, "online" => bool, "model" => string \| nil, "client_version" => string}`; replies `%{reason: "unauthorized"}` for another printer's topic, `%{reason: "unsupported_protocol"}` for another version |
| Print | server to printer | `"print"`, `%{"job_id" => string, "zpl" => string}` |
| Result | printer to server | `"print_result"`, `%{"job_id" => string, "ok" => true}` or `%{"job_id" => string, "ok" => false, "error" => string}` |
| Status | printer to server | `"status"`, `%{"online" => bool, "model" => string \| nil}`; replies `:ok` |
