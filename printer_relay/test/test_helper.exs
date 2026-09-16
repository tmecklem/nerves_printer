Application.put_env(:printer_relay, PrinterRelay.TestEndpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: 0],
  server: true,
  secret_key_base: String.duplicate("a", 64),
  pubsub_server: PrinterRelay.TestPubSub
)

children = [
  {Phoenix.PubSub, name: PrinterRelay.TestPubSub},
  {PrinterRelay, pubsub: PrinterRelay.TestPubSub},
  PrinterRelay.TestEndpoint
]

{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

Logger.configure(level: :warning)
ExUnit.start()
