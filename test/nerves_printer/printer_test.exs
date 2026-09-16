defmodule NervesPrinter.PrinterTest do
  use ExUnit.Case, async: true

  alias NervesPrinter.Printer

  doctest Printer

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    device_path = Path.join(tmp_dir, "lp0")
    id_path = Path.join(tmp_dir, "ieee1284_id")
    File.write!(id_path, "MFG:Zebra Technologies;CMD:EPL,ZPL;MDL:ZP 505;CLS:PRINTER;\n")

    printer =
      start_supervised!({Printer, name: nil, device_path: device_path, id_path: id_path})

    %{printer: printer, device_path: device_path, id_path: id_path}
  end

  test "rejects jobs while detached", %{printer: printer, device_path: device_path} do
    assert Printer.print(printer, "^XA^XZ") == {:error, :offline}
    refute File.exists?(device_path)
  end

  test "writes jobs to the device once attached", %{printer: printer, device_path: device_path} do
    Printer.attached(printer)
    assert Printer.print(printer, "^XA^FDHello^FS^XZ") == :ok
    assert File.read!(device_path) == "^XA^FDHello^FS^XZ"
  end

  test "reports the model from the IEEE 1284 ID", %{printer: printer} do
    assert Printer.status(printer) == %{online: false, model: nil}
    Printer.attached(printer)
    assert Printer.status(printer) == %{online: true, model: "ZP 505"}
  end

  test "reports an unknown model when the ID is unreadable", %{printer: printer, id_path: id_path} do
    File.rm!(id_path)
    Printer.attached(printer)
    assert Printer.status(printer) == %{online: true, model: nil}
  end

  test "notifies subscribers of changes", %{printer: printer} do
    assert Printer.subscribe(printer) == %{online: false, model: nil}

    Printer.attached(printer)
    assert_receive {:printer_relay_status, %{online: true, model: "ZP 505"}}

    Printer.detached(printer)
    assert_receive {:printer_relay_status, %{online: false, model: nil}}
  end

  test "returns write errors", %{printer: printer, tmp_dir: tmp_dir} do
    printer_in_missing_dir =
      start_supervised!(
        {Printer, name: nil, device_path: Path.join([tmp_dir, "missing", "lp0"])},
        id: :missing
      )

    Printer.attached(printer_in_missing_dir)
    assert Printer.print(printer_in_missing_dir, "^XA^XZ") == {:error, :enoent}
    assert Printer.status(printer).online == false
  end
end
