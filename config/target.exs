import Config

# Use Ringlogger as the logger backend and remove :console.
# See https://ring-logger.hexdocs.pm/readme.html for more information on
# configuring ring_logger.

config :logger, backends: [RingLogger]

# Use shoehorn to start the main application. See the shoehorn
# library documentation for more control in ordering how OTP
# applications are started and handling failures.

config :shoehorn, init: [:nerves_runtime, :nerves_pack]

# Enable the system startup guard to check that all OTP applications
# started. If they didn't and you're on a Nerves system that supports
# test runs of new firmware, the firmware will automatically roll
# back to the previous version. Delete this if implementing your own
# way of validating that firmware is good.
config :nerves_runtime, startup_guard_enabled: true

# Erlinit can be configured without a rootfs_overlay. See
# https://github.com/nerves-project/erlinit/ for more information on
# configuring erlinit.

# Advance the system clock on devices without a real-time clock.
config :nerves, :erlinit, update_clock: true

# Configure the device for SSH IEx prompt access and firmware updates
#
# * See https://nerves-ssh.hexdocs.pm/readme.html for general SSH configuration
# * See https://ssh-subsystem-fwup.hexdocs.pm/readme.html for firmware updates

keys =
  System.user_home!()
  |> Path.join(".ssh/id_{rsa,ecdsa,ed25519}.pub")
  |> Path.wildcard()

if keys == [],
  do:
    Mix.raise("""
    No SSH public keys found in ~/.ssh. An ssh authorized key is needed to
    log into the Nerves device and update firmware on it using ssh.
    See your project's config.exs for this error message.
    """)

config :nerves_ssh,
  authorized_keys: Enum.map(keys, &File.read!/1)

# Configure the network using vintage_net
#
# Update regulatory_domain to your 2-letter country code E.g., "US"
#
# See https://github.com/nerves-networking/vintage_net for more information
# WiFi credentials are read at build time so they stay out of the repo. Up to
# two networks are supported; the first is preferred when both are in range.
#
#     NERVES_WIFI_SSID=... NERVES_WIFI_PASSPHRASE=... \
#     NERVES_WIFI_SSID_2=... NERVES_WIFI_PASSPHRASE_2=... mix firmware
wifi_networks =
  for {suffix, priority} <- [{"", 100}, {"_2", 50}],
      ssid = System.get_env("NERVES_WIFI_SSID" <> suffix) do
    %{
      key_mgmt: :wpa_psk,
      ssid: ssid,
      psk: System.fetch_env!("NERVES_WIFI_PASSPHRASE" <> suffix),
      priority: priority
    }
  end

wifi_config =
  if wifi_networks == [] do
    %{type: VintageNetWiFi}
  else
    %{type: VintageNetWiFi, vintage_net_wifi: %{networks: wifi_networks}, ipv4: %{method: :dhcp}}
  end

config :vintage_net,
  regulatory_domain: System.get_env("NERVES_WIFI_REGDOM", "US"),
  config: [
    {"usb0", %{type: VintageNetDirect}},
    {"eth0",
     %{
       type: VintageNetEthernet,
       ipv4: %{method: :dhcp}
     }},
    {"wlan0", wifi_config}
  ]

# Connect to a PrinterRelay server when a URL is given at build time:
#
#     PRINTER_RELAY_URL=wss://example.com/printer_relay/websocket \
#     PRINTER_RELAY_TOKEN=... PRINTER_RELAY_PRINTER_ID=shop-1 mix firmware
#
# The printer id defaults to the device serial number.
if relay_url = System.get_env("PRINTER_RELAY_URL") do
  config :nerves_printer, PrinterRelay.Client,
    uri: relay_url,
    token: System.fetch_env!("PRINTER_RELAY_TOKEN"),
    printer_id: System.get_env("PRINTER_RELAY_PRINTER_ID")
end

config :mdns_lite,
  # The `hosts` key specifies what hostnames mdns_lite advertises.  `:hostname`
  # advertises the device's hostname.local. For the official Nerves systems, this
  # is "nerves-<4 digit serial#>.local".  The `"nerves"` host causes mdns_lite
  # to advertise "nerves.local" for convenience. If more than one Nerves device
  # is on the network, it is recommended to delete "nerves" from the list
  # because otherwise any of the devices may respond to nerves.local leading to
  # unpredictable behavior.

  hosts: [:hostname, "nerves"],
  ttl: 120,

  # Advertise the following services over mDNS.
  services: [
    %{
      protocol: "ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "sftp-ssh",
      transport: "tcp",
      port: 22
    },
    %{
      protocol: "epmd",
      transport: "tcp",
      port: 4369
    }
  ]

# Import target specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
# Uncomment to use target specific configurations

# import_config "#{Mix.target()}.exs"
