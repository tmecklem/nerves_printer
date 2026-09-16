defmodule PrinterRelay.PrinterChannelTest do
  use ExUnit.Case

  import Phoenix.ChannelTest

  @endpoint PrinterRelay.TestEndpoint

  setup do
    printer_id = "printer-#{System.unique_integer([:positive])}"
    {:ok, socket} = connect(PrinterRelay.TestSocket, %{"token" => "token-#{printer_id}"})
    %{printer_id: printer_id, socket: socket, topic: "printer_relay:printer:#{printer_id}"}
  end

  defp join_printer(c, params \\ %{}) do
    params = Map.merge(%{"protocol" => 1, "online" => true, "model" => "ZP 505"}, params)
    {:ok, _reply, channel} = subscribe_and_join(c.socket, c.topic, params)
    channel
  end

  defp print_async(printer_id, zpl, opts \\ []) do
    Task.async(fn -> PrinterRelay.print(printer_id, zpl, opts) end)
  end

  describe "connect" do
    test "rejects an unknown token" do
      assert connect(PrinterRelay.TestSocket, %{"token" => "nope"}) == :error
      assert connect(PrinterRelay.TestSocket, %{}) == :error
    end
  end

  describe "join" do
    test "lists the printer once joined", c do
      refute Enum.any?(PrinterRelay.printers(), &(&1.id == c.printer_id))

      join_printer(c)

      assert %{id: _, online: true, model: "ZP 505"} =
               Enum.find(PrinterRelay.printers(), &(&1.id == c.printer_id))
    end

    test "rejects a topic for a different printer", c do
      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(c.socket, "printer_relay:printer:someone-else", %{
                 "protocol" => 1
               })
    end

    test "rejects an unsupported protocol version", c do
      assert {:error, %{reason: "unsupported_protocol"}} =
               subscribe_and_join(c.socket, c.topic, %{"protocol" => 99})
    end
  end

  describe "print/3" do
    test "pushes the job and returns :ok when the printer succeeds", c do
      channel = join_printer(c)
      task = print_async(c.printer_id, "^XA^FDHi^FS^XZ")

      assert_push("print", %{"job_id" => job_id, "zpl" => "^XA^FDHi^FS^XZ"})
      push(channel, "print_result", %{"job_id" => job_id, "ok" => true})

      assert Task.await(task) == :ok
    end

    test "returns the printer's error", c do
      channel = join_printer(c)
      task = print_async(c.printer_id, "^XA^XZ")

      assert_push("print", %{"job_id" => job_id})
      push(channel, "print_result", %{"job_id" => job_id, "ok" => false, "error" => "enoent"})

      assert Task.await(task) == {:error, {:printer, "enoent"}}
    end

    test "returns :not_connected when no printer has joined", c do
      assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, :not_connected}
    end

    test "returns :offline when the printer reports no device attached", c do
      join_printer(c, %{"online" => false})
      assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, :offline}
    end

    test "returns :timeout when the printer never answers", c do
      join_printer(c)
      assert PrinterRelay.print(c.printer_id, "^XA^XZ", timeout: 50) == {:error, :timeout}
    end

    test "returns :disconnected when the channel goes away mid-job", c do
      channel = join_printer(c)
      task = print_async(c.printer_id, "^XA^XZ")
      assert_push("print", _)

      Process.unlink(channel.channel_pid)
      close(channel)

      assert Task.await(task) == {:error, :disconnected}
    end
  end

  describe "status" do
    test "updates the printer's online state and model", c do
      channel = join_printer(c)

      ref = push(channel, "status", %{"online" => false, "model" => nil})
      assert_reply(ref, :ok)

      assert %{online: false, model: nil} =
               Enum.find(PrinterRelay.printers(), &(&1.id == c.printer_id))

      assert PrinterRelay.print(c.printer_id, "^XA^XZ") == {:error, :offline}
    end
  end
end
