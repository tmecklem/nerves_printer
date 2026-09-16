defmodule NervesPrinter.StatusLedTest do
  use ExUnit.Case, async: false

  alias NervesPrinter.StatusLed

  @moduletag :tmp_dir
  @wifi ["interface", "wlan0", "connection"]

  describe "pattern/3" do
    test "fast blinks without WiFi, regardless of the server" do
      assert StatusLed.pattern(false, true, :connected) == :fast
      assert StatusLed.pattern(false, false, :disconnected) == :fast
    end

    test "slow blinks on WiFi while searching for the server" do
      assert StatusLed.pattern(true, true, :disconnected) == :slow
    end

    test "is solid on WiFi and connected to the server" do
      assert StatusLed.pattern(true, true, :connected) == :solid
    end

    test "is solid on WiFi when no server is configured" do
      assert StatusLed.pattern(true, false, :disconnected) == :solid
    end
  end

  defp start_led(tmp_dir, opts) do
    opts =
      Keyword.merge(
        [name: nil, led_path: tmp_dir, relay?: true, subscribe_wifi: fn -> false end],
        opts
      )

    start_supervised!({StatusLed, opts})
  end

  defp led(tmp_dir) do
    read = &(tmp_dir |> Path.join(&1) |> File.read!())

    case read.("trigger") do
      "none" -> {:solid, read.("brightness")}
      "timer" -> {:timer, read.("delay_on"), read.("delay_off")}
    end
  end

  defp sync(led), do: :sys.get_state(led)

  defp relay_connection(status) do
    :telemetry.execute([:printer_relay, :client, :connection], %{}, %{
      status: status,
      printer_id: "p1"
    })
  end

  test "fast blinks at startup without WiFi", %{tmp_dir: tmp_dir} do
    led = start_led(tmp_dir, subscribe_wifi: fn -> false end)
    sync(led)

    assert led(tmp_dir) == {:timer, "100", "100"}
  end

  test "follows WiFi and server connection changes", %{tmp_dir: tmp_dir} do
    led = start_led(tmp_dir, subscribe_wifi: fn -> true end)
    sync(led)
    assert led(tmp_dir) == {:timer, "1000", "1000"}

    relay_connection(:connected)
    sync(led)
    assert led(tmp_dir) == {:solid, "1"}

    send(led, {VintageNet, @wifi, :internet, :disconnected, %{}})
    sync(led)
    assert led(tmp_dir) == {:timer, "100", "100"}

    send(led, {VintageNet, @wifi, :disconnected, :lan, %{}})
    sync(led)
    assert led(tmp_dir) == {:solid, "1"}

    relay_connection(:disconnected)
    sync(led)
    assert led(tmp_dir) == {:timer, "1000", "1000"}
  end

  test "is solid on WiFi when no server is configured", %{tmp_dir: tmp_dir} do
    led = start_led(tmp_dir, relay?: false, subscribe_wifi: fn -> true end)
    sync(led)

    assert led(tmp_dir) == {:solid, "1"}
  end
end
