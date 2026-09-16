defmodule NervesPrinter.DeviceConfig.ImportTest do
  use ExUnit.Case, async: true

  alias NervesPrinter.DeviceConfig
  alias NervesPrinter.DeviceConfig.Import

  @moduletag :tmp_dir

  @valid """
  wifi_ssid=Shop WiFi
  wifi_passphrase=password1
  relay_url=wss://example.com/printer_relay/websocket
  relay_token=abc123
  printer_id=shop-1
  """

  setup %{tmp_dir: tmp_dir} do
    boot_dir = Path.join(tmp_dir, "autoboot")
    File.mkdir_p!(boot_dir)
    test_pid = self()

    opts = [
      boot_dir: boot_dir,
      data_path: Path.join([tmp_dir, "data", "printer_relay.conf"]),
      apply_wifi: fn networks ->
        send(test_pid, {:apply_wifi, networks})
        :ok
      end
    ]

    %{opts: opts, boot_dir: boot_dir, data_path: opts[:data_path]}
  end

  defp boot_file(c, name), do: Path.join(c.boot_dir, name)

  describe "sample file" do
    test "is written when missing", c do
      assert Import.run(c.opts) == :no_config
      assert File.read!(boot_file(c, "printer_relay.conf.sample")) == DeviceConfig.sample()
    end

    test "is refreshed when outdated", c do
      File.write!(boot_file(c, "printer_relay.conf.sample"), "old")
      Import.run(c.opts)
      assert File.read!(boot_file(c, "printer_relay.conf.sample")) == DeviceConfig.sample()
    end
  end

  test "does nothing else without a config file", c do
    assert Import.run(c.opts) == :no_config
    refute File.exists?(c.data_path)
    refute_received {:apply_wifi, _}
  end

  test "moves a valid config to the data partition and applies WiFi", c do
    File.write!(boot_file(c, "printer_relay.conf"), @valid)
    File.write!(boot_file(c, "printer_relay.conf.error.txt"), "stale")

    assert {:imported, %{relay: relay}} = Import.run(c.opts)

    assert relay[:printer_id] == "shop-1"
    assert File.read!(c.data_path) == @valid
    refute File.exists?(boot_file(c, "printer_relay.conf"))
    refute File.exists?(boot_file(c, "printer_relay.conf.error.txt"))
    assert_received {:apply_wifi, [%{ssid: "Shop WiFi", passphrase: "password1"}]}
  end

  test "keeps the current WiFi when the config has none", c do
    File.write!(boot_file(c, "printer_relay.conf"), "relay_url=ws://x/ws\nrelay_token=t\n")

    assert {:imported, _config} = Import.run(c.opts)
    refute_received {:apply_wifi, _}
  end

  test "replaces a previously imported config", c do
    File.mkdir_p!(Path.dirname(c.data_path))
    File.write!(c.data_path, "relay_url=ws://old/ws\nrelay_token=old\n")
    File.write!(boot_file(c, "printer_relay.conf"), @valid)

    Import.run(c.opts)

    assert File.read!(c.data_path) == @valid
  end

  test "leaves an invalid config in place and explains the problem", c do
    File.mkdir_p!(Path.dirname(c.data_path))
    File.write!(c.data_path, "relay_url=ws://old/ws\nrelay_token=old\n")
    File.write!(boot_file(c, "printer_relay.conf"), "relay_url=wss://x/ws\n")

    assert Import.run(c.opts) == {:error, "relay_token is required when relay_url is set"}

    assert File.exists?(boot_file(c, "printer_relay.conf"))

    assert File.read!(boot_file(c, "printer_relay.conf.error.txt")) =~
             "relay_token is required when relay_url is set"

    assert File.read!(c.data_path) == "relay_url=ws://old/ws\nrelay_token=old\n"
    refute_received {:apply_wifi, _}
  end

  test "leaves the config in place when WiFi can't be applied", c do
    File.write!(boot_file(c, "printer_relay.conf"), @valid)
    opts = Keyword.put(c.opts, :apply_wifi, fn _networks -> {:error, :bad_config} end)

    assert {:error, message} = Import.run(opts)
    assert message =~ "couldn't apply WiFi settings"
    assert File.exists?(boot_file(c, "printer_relay.conf"))
    refute File.exists?(c.data_path)
  end

  describe "load_relay/1" do
    test "returns the imported relay settings", c do
      File.mkdir_p!(Path.dirname(c.data_path))
      File.write!(c.data_path, @valid)

      assert Import.load_relay(c.data_path) == [
               uri: "wss://example.com/printer_relay/websocket",
               token: "abc123",
               printer_id: "shop-1"
             ]
    end

    test "returns nil without an imported config or relay settings", c do
      assert Import.load_relay(c.data_path) == nil

      File.mkdir_p!(Path.dirname(c.data_path))
      File.write!(c.data_path, "wifi_ssid=Shop\n")
      assert Import.load_relay(c.data_path) == nil
    end
  end
end
