defmodule PrinterRelay.TestPrinterTest do
  use ExUnit.Case

  alias PrinterRelay.TestPrinter

  defp unique_id, do: "test-printer-#{System.unique_integer([:positive])}"
  defp printer(id), do: Enum.find(PrinterRelay.printers(), &(&1.id == id))

  test "appears as a connected printer and receives jobs" do
    id = unique_id()
    start_supervised!({TestPrinter, id: id, notify: self()})

    assert %{online: true, model: "Test Printer"} = printer(id)
    assert PrinterRelay.print(id, "^XA^XZ") == :ok
    assert_received {:printer_relay_test_print, ^id, "^XA^XZ"}
  end

  test "returns a configured result" do
    id = unique_id()
    start_supervised!({TestPrinter, id: id, result: {:error, "out of labels"}})

    assert PrinterRelay.print(id, "^XA^XZ") == {:error, {:printer, "out of labels"}}
  end

  test "can go offline" do
    id = unique_id()
    pid = start_supervised!({TestPrinter, id: id, online: true})

    TestPrinter.set_online(pid, false)

    assert %{online: false} = printer(id)
    assert PrinterRelay.print(id, "^XA^XZ") == {:error, :offline}
  end

  test "disappears when stopped" do
    id = unique_id()
    start_supervised!({TestPrinter, id: id})
    stop_supervised!(TestPrinter)

    refute printer(id)
  end
end
