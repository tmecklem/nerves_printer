defmodule NervesPrinter.PrinterWatcherTest do
  use ExUnit.Case, async: true

  alias NervesPrinter.{Printer, PrinterWatcher}

  @moduletag :tmp_dir

  test "attaches and detaches as the device node comes and goes", %{tmp_dir: tmp_dir} do
    device_path = Path.join(tmp_dir, "lp0")
    printer = start_supervised!({Printer, name: nil, device_path: device_path})
    assert Printer.subscribe(printer).online == false

    start_supervised!(
      {PrinterWatcher, name: nil, printer: printer, device_path: device_path, interval: 10}
    )

    File.write!(device_path, "")
    assert_receive {:printer_status, %{online: true}}

    File.rm!(device_path)
    assert_receive {:printer_status, %{online: false}}
  end

  test "attaches immediately when the device is present at startup", %{tmp_dir: tmp_dir} do
    device_path = Path.join(tmp_dir, "lp0")
    File.write!(device_path, "")
    printer = start_supervised!({Printer, name: nil, device_path: device_path})
    Printer.subscribe(printer)

    start_supervised!({PrinterWatcher, name: nil, printer: printer, device_path: device_path})

    assert_receive {:printer_status, %{online: true}}
  end
end
