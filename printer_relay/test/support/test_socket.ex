defmodule PrinterRelay.TestSocket do
  @moduledoc false
  use PrinterRelay.Socket

  @impl PrinterRelay.Socket
  def authenticate("token-" <> printer_id, _connect_info), do: {:ok, printer_id}
  def authenticate(_token, _connect_info), do: :error
end
