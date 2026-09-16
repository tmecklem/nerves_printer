# Nerves Label Printer: Research and Plan

Raspberry Pi Zero 2 W running Nerves, a Zebra ZP 450 or ZP 505 on the USB
port, and a WebSocket client that receives ZPL from the Equipment Tracker
server and prints it as it arrives.

Research date: 2026-09-16. Versions referenced: Nerves 1.15.0,
nerves_system_rpi3 v2.1.2 (kernel 6.18, nerves_system_br 1.34.x).

## Summary of findings

- **A custom Nerves system is required.** No official Pi system enables
  `CONFIG_USB_PRINTER` (the `usblp` driver), so `/dev/usb/lp0` never appears.
  A rootfs overlay cannot fix this: it is a kernel driver, not a file.
- **The fix is one line** in the kernel defconfig: `CONFIG_USB_PRINTER=y`.
- **Base system is `nerves_system_rpi3`**, not `rpi0_2`. The Zero 2 W uses the
  BCM2710 (Pi 3 family). rpi3 ships `bcm2710-rpi-zero-2-w.dtb`, runs the USB
  port in host mode, and includes the `brcmfmac` onboard WiFi driver.
  `rpi0_2` and `rpi3a` are gadget-mode systems with no host-class USB drivers.
  `rpi0` and `rpi` are BCM2708 (armv6) and will not boot a Zero 2 W.
- **Both printers use the same driver path.** ZP 450 (UPS-branded) and ZP 505
  (FedEx-branded) are rebadged GK420d-class printers: USB printer class,
  vendor ID `0x0a5f`, ZPL II and EPL. Use ZPL only; there is a known report of
  the ZP 505 ignoring EPL over USB while ZPL works.
- **Build the system in GitHub Actions on a fork**, not locally. The upstream
  CI already builds, packages, and publishes the artifact to a GitHub release,
  which is where `artifact_sites` already looks.
- **Develop the app on the Mac.** After the one-time system build, the loop is
  `mix firmware && mix upload` plus remote IEx over SSH.

## Hardware

| Item | Detail |
|---|---|
| Board | Raspberry Pi Zero 2 W (BCM2710A1, 512 MB, armv7 under rpi3) |
| USB | Single micro-USB OTG data port. Needs a micro-B male to USB-A female OTG adapter. Printer is self-powered. |
| Power | Separate micro-USB PWR port |
| WiFi | Onboard, `brcmfmac`, configured through VintageNet |
| Printer | Zebra ZP 450 or ZP 505, one at a time, hot-pluggable |

Identifying which printer is attached once `usblp` binds:

```
cat /sys/class/usbmisc/lp0/device/ieee1284_id
# MFG:Zebra Technologies;CMD:EPL,ZPL;MDL:ZP 505;...
```

Or send `~HI` to `/dev/usb/lp0` and read the reply from the same node (the
interface is bidirectional).

## Step 1: Custom system fork

1. Clone the tagged release, not `main`:
   ```
   git clone https://github.com/nerves-project/nerves_system_rpi3.git printer_relay_rpi3 -b v2.1.2
   cd printer_relay_rpi3
   git remote rename origin upstream
   git remote add origin git@github.com:tmecklem/printer_relay_rpi3.git
   git checkout -b main
   ```
   The GitHub repo must be named `printer_relay_rpi3` because CI derives the artifact
   name from the repo name (`mix nerves.artifact ${GITHUB_REPOSITORY#*/}`).

2. `linux-6.18.defconfig`: add next to `CONFIG_USB_STORAGE=y` (around line 262):
   ```
   CONFIG_USB_PRINTER=y
   ```
   Built-in rather than `=m` so it does not depend on nerves_uevent modprobe
   timing. `CONFIG_USB=y` already satisfies the dependency; no menuconfig
   needed.

3. `mix.exs`: change three things only.
   - `defmodule NervesSystemRpi3.MixProject` to `defmodule CustomRpi3.MixProject`
   - `@github_organization "nerves-project"` to `"tmecklem"`
   - `@app :nerves_system_rpi3` to `:printer_relay_rpi3`

4. `VERSION`: bump (for example `2.1.2-usblp.1`). `CHANGELOG.md`: add a
   `## v2.1.2-usblp.1` heading; the deploy step greps release notes from it.

5. `.github/workflows/ci.yml`: two edits for a fork.
   - Change every `runs-on: blacksmith-4vcpu-ubuntu-2404` to `runs-on: ubuntu-24.04`.
   - In the `get-br-dependencies` job, delete `push-to-download-site: true`
     and the `download-site-bucket-uri`, `aws-role`, `aws-region` inputs.
     Without them the action runs `make source` locally instead of pushing
     to S3.

6. Commit, push `main`, then push a tag matching the CHANGELOG heading:
   ```
   git tag v2.1.2-usblp.1 && git push origin main --tags
   ```
   CI builds (roughly an hour) and creates a **draft** release with
   `printer_relay_rpi3-portable-<version>-<checksum>.tar.gz`. Publish the draft;
   the Nerves artifact resolver only sees published releases.

Keeping up with upstream later: `git fetch upstream && git merge upstream/main`.

## Step 2: Nerves app (this directory)

```
mix nerves.new nerves_printer --target rpi3
```

`mix.exs` system dep, replacing the stock rpi3 entry:

```elixir
{:printer_relay_rpi3, github: "tmecklem/printer_relay_rpi3", tag: "v2.1.2-usblp.1",
 runtime: false, targets: :printer_relay_rpi3}
```

and add `:printer_relay_rpi3` to `@all_targets`. Build with `MIX_TARGET=printer_relay_rpi3`.
`mix deps.get` downloads the prebuilt artifact from the GitHub release.

Suggested dependencies:

| Dep | Purpose |
|---|---|
| `nerves_pack` | VintageNet WiFi, SSH, mDNS, nerves_uevent (standard) |
| `slipstream` | Phoenix Channels WebSocket client to Equipment Tracker |
| `nerves_uevent` / `property_table` | Hotplug detection (already in nerves_pack) |

Modules:

- **`NervesPrinter.Printer`** (GenServer). Owns the device path
  (`/dev/usb/lp0`, configurable so tests can point at a temp file). Opens with
  `File.open(path, [:write, :binary])` and `IO.binwrite`s each ZPL job.
  Reports `{:ok, model}` after reading `ieee1284_id` on attach. Queues jobs
  while the printer is absent, or rejects them, depending on what the server
  expects.
- **`NervesPrinter.PrinterWatcher`**. Subscribes to `NervesUEvent` via
  PropertyTable for the `usbmisc` device appearing and disappearing, or polls
  for the device node every second. Tells the Printer GenServer to open or
  close.
- **`NervesPrinter.Socket`** (Slipstream). Joins a channel such as
  `printer:<serial>` on the server, receives `{"print", %{"zpl" => zpl}}`
  events, hands them to Printer, and replies with success or failure so the
  server can retry. Reconnects with backoff. Reports printer model and
  online status on join.

Server side (equipment_tracker): a `PrinterChannel` plus a socket, and a
PubSub broadcast that pushes ZPL to whichever printer channel is subscribed.

Tests: printer logic against a temp file path; channel behaviour against a
Slipstream test socket; no hardware needed for the suite.

## Step 3: Dev loop

1. First boot: `mix firmware && mix burn` to an SD card. Set WiFi credentials
   via `config/target.exs` VintageNet config or `NERVES_WIFI_*` env vars at
   build time.
2. Every iteration after that: `mix firmware && mix upload nerves.local`
   (about 1 to 2 minutes over WiFi).
3. Hardware exploration: `ssh nerves.local` for remote IEx. Useful one-liners:
   ```elixir
   File.ls!("/dev/usb")
   File.read!("/sys/class/usbmisc/lp0/device/ieee1284_id")
   File.write!("/dev/usb/lp0", "^XA^FO50,50^ADN,36,20^FDHello^FS^XZ")
   ```

## While CI builds

- Scaffold the app and write the Printer, PrinterWatcher, and Socket modules
  with tests (no hardware needed).
- Add the PrinterChannel to equipment_tracker.
- Optional printer sanity check on the Mac: plug the Zebra in,
  `ioreg -p IOUSB` shows the model string, and a CUPS raw queue
  (`lpadmin -p zebra -E -v usb://... -m raw`, then `lp -d zebra -o raw file.zpl`)
  confirms the printer is in ZPL mode.

## Rejected alternatives

- **Rootfs overlay**: cannot add a kernel driver.
- **Out-of-tree `usblp.ko`**: needs the same kernel build tree as a custom
  system, so no savings, and fragile across upgrades.
- **Raw usbfs bulk writes from Elixir**: needs a NIF or port for ioctls; no
  maintained Elixir libusb binding.
- **USB-serial adapter to the printer's RS-232 port**: the stock kernel has
  FTDI/CP210x/CH341 modules, but only the ZP 505 has a serial port.
- **Docker or UTM VM on the Mac**: works (aarch64 Linux container builds
  fine), but `mix nerves.system.shell` is degraded since OTP 26, APFS
  case-insensitivity needs a separate volume, and 20 GB plus of scratch
  space for a one-line change is not worth it.
- **Raspberry Pi OS for development**: Elixir on a Zero 2 W means stale apt
  OTP or hours compiling, and everything you would try there is the same
  shell command in Nerves remote IEx.
- **`nerves_system_rpi0_2`**: gadget mode, no host-class USB drivers.

## Sources

- nerves_system_rpi3 (`fwup.conf.eex`, `config.txt`, `linux-6.18.defconfig`):
  https://github.com/nerves-project/nerves_system_rpi3
- nerves_system_rpi0_2 README (gadget mode, Zero 2 W):
  https://github.com/nerves-project/nerves_system_rpi0_2
- Customizing Your Nerves System: https://hexdocs.pm/nerves/customizing-systems.html
- Building Nerves Systems (nerves_systems repo): https://hexdocs.pm/nerves/building-systems.html
- CI actions used by official systems: https://github.com/gridpoint-com/actions-nerves-system
- nerves_uevent (module autoload, PropertyTable): https://github.com/nerves-project/nerves_uevent
- Zebra ZP 505 datasheet: https://zebra.com/content/dam/zebra_new_ia/en-us/support-and-downloads/misc/ZP505_datasheet.pdf
- Zebra ZP 450 user guide: https://files.comtrol.com/contribs/devicemaster/help_files/cables/Cable_Vendor_pinouts/Zebra%20ZP%20450%20CTP/Zebra-%20UM-ZP450CTP.pdf
- ZP 505 EPL over USB issue, ZPL fine: https://groups.google.com/g/qz-print/c/W9nxj6zZGrA
- Nerves on Raspberry Pi Zero 2 W (forum): https://elixirforum.com/t/nerves-on-raspberry-pi-zero-2-w/58659
