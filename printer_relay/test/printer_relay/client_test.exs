defmodule PrinterRelay.ClientTest do
  use Slipstream.SocketTest

  alias PrinterRelay.Client

  @topic "printer_relay:printer:shop-1"

  defp start_client(backend_arg \\ %{}) do
    backend_arg =
      Map.merge(
        %{test: self(), status: %{online: true, model: "ZP 505"}, result: :ok},
        backend_arg
      )

    start_supervised!(
      {Client,
       name: nil,
       uri: "ws://relay.test/printer_relay/websocket",
       token: "secret",
       printer_id: "shop-1",
       backend: {PrinterRelay.TestBackend, backend_arg},
       test_mode?: true}
    )
  end

  test "joins the printer topic with protocol version and status" do
    client = start_client()

    connect_and_assert_join(
      client,
      @topic,
      %{"protocol" => 1, "online" => true, "model" => "ZP 505", "client_version" => vsn},
      :ok
    )

    assert vsn == to_string(Application.spec(:printer_relay, :vsn))
  end

  test "prints jobs through the backend and reports success" do
    client = start_client()
    connect_and_assert_join(client, @topic, _, :ok)

    push(client, @topic, "print", %{"job_id" => "1", "zpl" => "^XA^XZ"})

    assert_receive {:backend_print, "^XA^XZ"}
    assert_push(@topic, "print_result", %{"job_id" => "1", "ok" => true})
  end

  test "reports backend errors" do
    client = start_client(%{result: {:error, :enoent}})
    connect_and_assert_join(client, @topic, _, :ok)

    push(client, @topic, "print", %{"job_id" => "2", "zpl" => "^XA^XZ"})

    assert_push(@topic, "print_result", %{"job_id" => "2", "ok" => false, "error" => ":enoent"})
  end

  test "pushes status changes while joined" do
    client = start_client()
    connect_and_assert_join(client, @topic, _, :ok)

    send(client, {:printer_relay_status, %{online: false, model: nil}})

    assert_push(@topic, "status", %{"online" => false, "model" => nil})
  end

  test "rejoins with the latest status after the topic closes" do
    client = start_client()
    connect_and_assert_join(client, @topic, _, :ok)

    send(client, {:printer_relay_status, %{online: false, model: nil}})
    assert_push(@topic, "status", _)

    disconnect(client, :heartbeat_timeout)
    connect_and_assert_join(client, @topic, %{"online" => false}, :ok, 2_000)
  end

  test "puts the token in the connect URI" do
    assert Client.connect_uri("ws://relay.test/printer_relay/websocket", "s3cr3t") ==
             "ws://relay.test/printer_relay/websocket?token=s3cr3t"

    assert Client.connect_uri("wss://relay.test/socket/websocket?x=1", "a b") ==
             "wss://relay.test/socket/websocket?x=1&token=a+b"
  end
end
