defmodule NervesPrinter.ApplicationTest do
  use ExUnit.Case, async: true

  alias NervesPrinter.Application

  test "starts no relay client without a URI" do
    assert Application.relay_children([]) == []
    assert Application.relay_children(uri: nil, token: "t") == []
  end

  test "starts a relay client backed by the printer" do
    assert [{PrinterRelay.Client, opts}] =
             Application.relay_children(uri: "wss://relay.test/ws", token: "t", printer_id: "p1")

    assert opts[:uri] == "wss://relay.test/ws"
    assert opts[:token] == "t"
    assert opts[:printer_id] == "p1"
    assert opts[:backend] == {NervesPrinter.Printer, NervesPrinter.Printer}
  end

  test "defaults the printer id to the device serial number" do
    assert [{PrinterRelay.Client, opts}] =
             Application.relay_children(uri: "wss://relay.test/ws", token: "t")

    assert opts[:printer_id] == Nerves.Runtime.serial_number()
  end

  test "treats unset config values as missing" do
    assert [{PrinterRelay.Client, opts}] =
             Application.relay_children(uri: "wss://relay.test/ws", token: "t", printer_id: nil)

    assert opts[:printer_id] == Nerves.Runtime.serial_number()
  end
end
