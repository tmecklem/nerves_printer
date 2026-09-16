defmodule NervesPrinter.DeviceConfigTest do
  use ExUnit.Case, async: true

  alias NervesPrinter.DeviceConfig

  describe "parse/1" do
    test "reads WiFi networks and relay settings" do
      text = """
      # comment
      wifi_ssid=Shop WiFi
      wifi_passphrase=pa#ss=word

      wifi_ssid_2 = Backup
      wifi_passphrase_2 = backup-pass
      relay_url=wss://example.com/printer_relay/websocket
      relay_token=abc123
      printer_id=shop-1
      """

      assert DeviceConfig.parse(text) ==
               {:ok,
                %{
                  wifi_networks: [
                    %{ssid: "Shop WiFi", passphrase: "pa#ss=word", priority: 100},
                    %{ssid: "Backup", passphrase: "backup-pass", priority: 50}
                  ],
                  relay: [
                    uri: "wss://example.com/printer_relay/websocket",
                    token: "abc123",
                    printer_id: "shop-1"
                  ]
                }}
    end

    test "treats blank values as unset" do
      assert DeviceConfig.parse("wifi_ssid=\nrelay_url=\nprinter_id=\n") ==
               {:ok, %{wifi_networks: [], relay: nil}}
    end

    test "leaves the printer id out when unset" do
      assert {:ok, %{relay: relay}} =
               DeviceConfig.parse(
                 "relay_url=ws://10.0.0.2:4000/printer_relay/websocket\nrelay_token=t"
               )

      refute Keyword.has_key?(relay, :printer_id)
    end

    test "allows an open WiFi network" do
      assert {:ok, %{wifi_networks: [%{ssid: "Guest", passphrase: nil}]}} =
               DeviceConfig.parse("wifi_ssid=Guest")
    end

    test "handles Windows line endings" do
      assert {:ok, %{relay: [uri: "ws://x/ws", token: "t"]}} =
               DeviceConfig.parse("relay_url=ws://x/ws\r\nrelay_token=t\r\n")
    end

    test "rejects unknown keys so typos don't go unnoticed" do
      assert DeviceConfig.parse("relay_tokn=abc") ==
               {:error, "line 1: unknown setting \"relay_tokn\""}
    end

    test "rejects lines without =" do
      assert DeviceConfig.parse("\nwifi_ssid Shop") ==
               {:error, "line 2: expected setting=value"}
    end

    test "requires a token with a relay URL" do
      assert DeviceConfig.parse("relay_url=wss://x/ws") ==
               {:error, "relay_token is required when relay_url is set"}
    end

    test "requires a ws:// or wss:// relay URL" do
      assert DeviceConfig.parse("relay_url=https://x/ws\nrelay_token=t") ==
               {:error, "relay_url must start with ws:// or wss://"}
    end

    test "requires WiFi passphrases to be 8 to 63 characters" do
      assert DeviceConfig.parse("wifi_ssid=Shop\nwifi_passphrase=short") ==
               {:error, "wifi_passphrase must be 8 to 63 characters"}
    end

    test "requires an SSID for a passphrase" do
      assert DeviceConfig.parse("wifi_passphrase_2=longenough") ==
               {:error, "wifi_passphrase_2 is set without wifi_ssid_2"}
    end
  end

  describe "sample/0" do
    test "documents every setting and parses as an empty configuration" do
      sample = DeviceConfig.sample()

      for key <-
            ~w(wifi_ssid wifi_passphrase wifi_ssid_2 wifi_passphrase_2 relay_url relay_token printer_id) do
        assert sample =~ "#{key}="
      end

      assert DeviceConfig.parse(sample) == {:ok, %{wifi_networks: [], relay: nil}}
    end
  end

  describe "vintage_net_wifi/1" do
    test "builds a VintageNet WiFi configuration" do
      networks = [
        %{ssid: "Shop", passphrase: "password1", priority: 100},
        %{ssid: "Guest", passphrase: nil, priority: 50}
      ]

      assert DeviceConfig.vintage_net_wifi(networks) == %{
               type: VintageNetWiFi,
               vintage_net_wifi: %{
                 networks: [
                   %{key_mgmt: :wpa_psk, ssid: "Shop", psk: "password1", priority: 100},
                   %{key_mgmt: :none, ssid: "Guest", priority: 50}
                 ]
               },
               ipv4: %{method: :dhcp}
             }
    end
  end
end
