defmodule PrinterRelay.ClusterTest do
  @moduledoc """
  A printer connected to one node is visible and printable from another.
  """
  use ExUnit.Case

  @moduletag :distributed

  setup_all do
    unless Node.alive?() do
      {_, 0} = System.cmd("epmd", ["-daemon"])
      {:ok, _} = :net_kernel.start([:"printer_relay_test@127.0.0.1", :longnames])
    end

    code_path = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])

    {:ok, peer, node} =
      :peer.start(%{name: :printer_relay_peer, host: ~c"127.0.0.1", args: code_path})

    {:ok, _} = :erpc.call(node, Application, :ensure_all_started, [:phoenix_pubsub])

    # Children go under kernel_sup: anything linked to the erpc call would exit with it.
    for child <- [
          {Phoenix.PubSub, name: PrinterRelay.TestPubSub},
          {PrinterRelay, pubsub: PrinterRelay.TestPubSub}
        ] do
      {:ok, _} = :erpc.call(node, Supervisor, :start_child, [:kernel_sup, child])
    end

    on_exit(fn -> :peer.stop(peer) end)
    %{node: node}
  end

  defp eventually(fun, attempts \\ 250) do
    cond do
      result = fun.() -> result
      attempts == 0 -> flunk("condition never became true")
      true -> Process.sleep(40) && eventually(fun, attempts - 1)
    end
  end

  test "prints to a printer connected to another node", %{node: node} do
    :ok = PrinterRelay.subscribe()
    id = "remote-#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      :erpc.call(node, GenServer, :start, [PrinterRelay.TestPrinter, [id: id, notify: self()]])

    assert_receive {:printer_relay, :printers_changed}, 10_000
    eventually(fn -> Enum.find(PrinterRelay.printers(), &(&1.id == id)) end)

    assert PrinterRelay.print(id, "^XA^FDremote^FS^XZ") == :ok
    assert_received {:printer_relay_test_print, ^id, "^XA^FDremote^FS^XZ"}
  end
end
