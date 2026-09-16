defmodule NervesPrinter.DeviceConfig do
  @moduledoc """
  Device settings read from a `printer_relay.conf` file.

  The file uses `setting=value` lines and `#` comments. See
  `priv/printer_relay.conf.sample` for every setting.
  """

  @wifi_networks [{"", 100}, {"_2", 50}]
  @keys ~w(wifi_ssid wifi_passphrase wifi_ssid_2 wifi_passphrase_2 relay_url relay_token printer_id)

  @type wifi_network :: %{ssid: String.t(), passphrase: String.t() | nil, priority: integer()}
  @type t :: %{wifi_networks: [wifi_network()], relay: keyword() | nil}

  @doc """
  Parses and validates the contents of a config file.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(text) do
    with {:ok, settings} <- parse_lines(text),
         {:ok, wifi_networks} <- wifi_networks(settings),
         {:ok, relay} <- relay(settings) do
      {:ok, %{wifi_networks: wifi_networks, relay: relay}}
    end
  end

  @doc "The documented sample config file."
  @spec sample() :: String.t()
  def sample do
    :nerves_printer
    |> :code.priv_dir()
    |> Path.join("printer_relay.conf.sample")
    |> File.read!()
  end

  @doc """
  Builds the VintageNet configuration for `wlan0` from parsed WiFi networks.
  """
  @spec vintage_net_wifi([wifi_network()]) :: map()
  def vintage_net_wifi(networks) do
    %{
      type: VintageNetWiFi,
      vintage_net_wifi: %{networks: Enum.map(networks, &vintage_net_network/1)},
      ipv4: %{method: :dhcp}
    }
  end

  defp vintage_net_network(%{passphrase: nil} = network) do
    %{key_mgmt: :none, ssid: network.ssid, priority: network.priority}
  end

  defp vintage_net_network(network) do
    %{key_mgmt: :wpa_psk, ssid: network.ssid, psk: network.passphrase, priority: network.priority}
  end

  defp parse_lines(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, %{}}, fn {line, number}, {:ok, settings} ->
      case parse_line(String.trim(line)) do
        :skip -> {:cont, {:ok, settings}}
        {:ok, key, value} -> {:cont, {:ok, Map.put(settings, key, value)}}
        {:error, message} -> {:halt, {:error, "line #{number}: #{message}"}}
      end
    end)
  end

  defp parse_line(""), do: :skip
  defp parse_line("#" <> _comment), do: :skip

  defp parse_line(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        key = String.trim(key)
        value = String.trim(value)

        cond do
          key not in @keys -> {:error, "unknown setting #{inspect(key)}"}
          value == "" -> :skip
          true -> {:ok, key, value}
        end

      [_no_equals] ->
        {:error, "expected setting=value"}
    end
  end

  defp wifi_networks(settings) do
    Enum.reduce_while(@wifi_networks, {:ok, []}, fn {suffix, priority}, {:ok, networks} ->
      ssid = settings["wifi_ssid" <> suffix]
      passphrase = settings["wifi_passphrase" <> suffix]

      cond do
        passphrase && !ssid ->
          {:halt, {:error, "wifi_passphrase#{suffix} is set without wifi_ssid#{suffix}"}}

        passphrase && String.length(passphrase) not in 8..63 ->
          {:halt, {:error, "wifi_passphrase#{suffix} must be 8 to 63 characters"}}

        ssid ->
          network = %{ssid: ssid, passphrase: passphrase, priority: priority}
          {:cont, {:ok, networks ++ [network]}}

        true ->
          {:cont, {:ok, networks}}
      end
    end)
  end

  defp relay(%{"relay_url" => url} = settings) do
    cond do
      not String.starts_with?(url, ["ws://", "wss://"]) ->
        {:error, "relay_url must start with ws:// or wss://"}

      !settings["relay_token"] ->
        {:error, "relay_token is required when relay_url is set"}

      true ->
        relay = [uri: url, token: settings["relay_token"]]

        relay =
          if settings["printer_id"],
            do: relay ++ [printer_id: settings["printer_id"]],
            else: relay

        {:ok, relay}
    end
  end

  defp relay(_settings), do: {:ok, nil}
end
