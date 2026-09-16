defmodule PrinterRelay.TestBackend do
  @moduledoc false
  @behaviour PrinterRelay.Client.Backend

  # arg: %{test: pid, status: status, result: :ok | {:error, term}}
  @impl true
  def subscribe(arg), do: arg.status

  @impl true
  def print(arg, zpl) do
    send(arg.test, {:backend_print, zpl})
    arg.result
  end
end
