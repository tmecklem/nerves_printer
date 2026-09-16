defmodule PrinterRelay.TestEndpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :printer_relay

  socket("/printer_relay", PrinterRelay.TestSocket, websocket: true, longpoll: false)
end
