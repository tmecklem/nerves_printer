defmodule PrinterRelay.SubscribeTest do
  use ExUnit.Case

  alias PrinterRelay.TestPrinter

  test "notifies subscribers when printers connect, change, and disconnect" do
    :ok = PrinterRelay.subscribe()
    id = "subscribed-#{System.unique_integer([:positive])}"

    pid = start_supervised!({TestPrinter, id: id})
    assert_receive {:printer_relay, :printers_changed}

    TestPrinter.set_online(pid, false)
    assert_receive {:printer_relay, :printers_changed}

    stop_supervised!(TestPrinter)
    assert_receive {:printer_relay, :printers_changed}
  end
end
