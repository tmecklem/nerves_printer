defmodule PrinterRelay.Client.Backend do
  @moduledoc """
  The printer a `PrinterRelay.Client` prints to.

  The client is configured with `backend: {module, arg}`; `arg` is passed to
  every callback.
  """

  @type status :: %{online: boolean(), model: String.t() | nil}

  @doc """
  Returns the current status and subscribes the calling process to changes,
  delivered as `{:printer_relay_status, status}` messages.
  """
  @callback subscribe(arg :: term()) :: status()

  @doc "Prints `zpl`, returning once the printer has accepted it."
  @callback print(arg :: term(), zpl :: binary()) :: :ok | {:error, term()}
end
