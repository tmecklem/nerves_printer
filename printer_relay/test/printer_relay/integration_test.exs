defmodule PrinterRelay.IntegrationTest do
  @moduledoc """
  A real client connected to a real endpoint over a WebSocket.
  """
  use ExUnit.Case

  @moduletag :capture_log

  alias PrinterRelay.{Client, TestEndpoint}

  setup do
    {:ok, {_ip, port}} = TestEndpoint.server_info(:http)
    printer_id = "e2e-#{System.unique_integer([:positive])}"
    %{uri: "ws://127.0.0.1:#{port}/printer_relay/websocket", printer_id: printer_id}
  end

  defp start_client(c, opts \\ []) do
    backend_arg = %{
      test: self(),
      status: %{online: true, model: "ZP 505"},
      result: Keyword.get(opts, :result, :ok)
    }

    start_supervised!(
      {Client,
       name: nil,
       uri: c.uri,
       token: Keyword.get(opts, :token, "token-#{c.printer_id}"),
       printer_id: c.printer_id,
       backend: {PrinterRelay.TestBackend, backend_arg}}
    )
  end

  defp printer(id), do: Enum.find(PrinterRelay.printers(), &(&1.id == id))

  defp eventually(fun, attempts \\ 100) do
    cond do
      result = fun.() -> result
      attempts == 0 -> flunk("condition never became true")
      true -> Process.sleep(20) && eventually(fun, attempts - 1)
    end
  end

  test "prints over a real WebSocket", c do
    start_client(c)
    eventually(fn -> printer(c.printer_id) end)

    assert PrinterRelay.print(c.printer_id, "^XA^FDe2e^FS^XZ") == :ok
    assert_received {:backend_print, "^XA^FDe2e^FS^XZ"}
  end

  test "returns the device's error over a real WebSocket", c do
    start_client(c, result: {:error, :enoent})
    eventually(fn -> printer(c.printer_id) end)

    assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, {:printer, ":enoent"}}
  end

  test "propagates status changes", c do
    client = start_client(c)
    eventually(fn -> printer(c.printer_id) end)

    send(client, {:printer_relay_status, %{online: false, model: nil}})

    eventually(fn -> match?(%{online: false}, printer(c.printer_id)) end)
    assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, :offline}
  end

  test "reconnects and rejoins after the server drops the connection", c do
    start_client(c)
    %{connected_at: first} = eventually(fn -> printer(c.printer_id) end)

    TestEndpoint.broadcast("printer_relay_socket:#{c.printer_id}", "disconnect", %{})

    eventually(fn -> match?(%{connected_at: t} when t > first, printer(c.printer_id)) end)
    assert PrinterRelay.print(c.printer_id, "^XA^XZ") == :ok
  end

  test "never joins with a bad token", c do
    start_client(c, token: "wrong")
    Process.sleep(300)

    refute printer(c.printer_id)
    assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, :not_connected}
  end
end
