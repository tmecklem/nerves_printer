defmodule NervesPrinter.SocketTest do
  use Slipstream.SocketTest

  alias NervesPrinter.{Printer, Socket}

  @moduletag :tmp_dir
  @topic "printer:test-1"

  setup %{tmp_dir: tmp_dir} do
    device_path = Path.join(tmp_dir, "lp0")
    printer = start_supervised!({Printer, name: nil, device_path: device_path})

    socket =
      start_supervised!(
        {Socket,
         name: nil,
         printer: printer,
         printer_id: "test-1",
         uri: "ws://test.invalid/socket/websocket",
         test_mode?: true}
      )

    %{printer: printer, socket: socket, device_path: device_path}
  end

  test "joins with the printer status", %{socket: socket} do
    connect_and_assert_join(socket, @topic, %{"online" => false, "model" => nil}, :ok)
  end

  test "prints jobs and reports success", c do
    Printer.attached(c.printer)
    # Let the printer notify the socket before it connects.
    Printer.status(c.printer)
    :sys.get_state(c.socket)

    connect_and_assert_join(c.socket, @topic, %{"online" => true}, :ok)

    push(c.socket, @topic, "print", %{"job_id" => 7, "zpl" => "^XA^XZ"})

    assert_push(@topic, "print_result", %{"job_id" => 7, "ok" => true})
    assert File.read!(c.device_path) == "^XA^XZ"
  end

  test "reports failure when the printer is offline", c do
    connect_and_assert_join(c.socket, @topic, _, :ok)

    push(c.socket, @topic, "print", %{"job_id" => 8, "zpl" => "^XA^XZ"})

    assert_push(@topic, "print_result", %{"job_id" => 8, "ok" => false, "error" => ":offline"})
  end

  test "pushes status changes while joined", c do
    connect_and_assert_join(c.socket, @topic, _, :ok)

    Printer.attached(c.printer)

    assert_push(@topic, "status", %{"online" => true})
  end
end
