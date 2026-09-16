defmodule NervesPrinter.DeviceConfig.Import do
  @moduledoc """
  Imports `printer_relay.conf` from the SD card's AUTOBOOT partition.

  AUTOBOOT is a small FAT partition that firmware updates never rewrite, and
  it shows up when the SD card is plugged into a computer. On boot:

  * `printer_relay.conf.sample` is written (or refreshed) for reference.
  * A valid `printer_relay.conf` is moved to the data partition, which also
    survives firmware updates, and its WiFi settings are applied.
  * An invalid one stays on the card next to `printer_relay.conf.error.txt`,
    which explains what to fix.
  """

  require Logger

  alias NervesPrinter.DeviceConfig

  @config_file "printer_relay.conf"
  @sample_file "printer_relay.conf.sample"
  @error_file "printer_relay.conf.error.txt"

  @autoboot_device "/dev/mmcblk0p1"
  @mount_point "/tmp/autoboot"
  @data_path "/data/printer_relay.conf"

  @doc "Where imported settings are kept on the device."
  def data_path, do: @data_path

  @doc """
  Mounts AUTOBOOT, imports any config, and unmounts. Never raises, so a
  problem with the card can't stop the firmware from booting.
  """
  @spec run_on_device() :: :no_config | {:imported, DeviceConfig.t()} | {:error, term()}
  def run_on_device do
    with :ok <- File.mkdir_p(@mount_point),
         :ok <- mount() do
      try do
        run(boot_dir: @mount_point, data_path: @data_path, apply_wifi: &apply_vintage_net_wifi/1)
      after
        unmount()
      end
    end
    |> log_result()
  rescue
    exception ->
      Logger.error("DeviceConfig: import failed: #{Exception.message(exception)}")
      {:error, exception}
  end

  @doc """
  Imports from a mounted AUTOBOOT directory.

  ## Options

    * `:boot_dir` - the mounted AUTOBOOT partition
    * `:data_path` - where imported settings are kept
    * `:apply_wifi` - applies parsed WiFi networks, returning `:ok` or `{:error, reason}`
  """
  @spec run(keyword()) :: :no_config | {:imported, DeviceConfig.t()} | {:error, String.t()}
  def run(opts) do
    boot_dir = Keyword.fetch!(opts, :boot_dir)
    write_sample(boot_dir)

    case File.read(Path.join(boot_dir, @config_file)) do
      {:ok, text} -> import(text, boot_dir, opts)
      {:error, :enoent} -> :no_config
      {:error, reason} -> fail(boot_dir, "couldn't read the file (#{inspect(reason)})")
    end
  end

  @doc """
  Returns the relay settings imported onto the device, or nil.
  """
  @spec load_relay(Path.t()) :: keyword() | nil
  def load_relay(data_path \\ @data_path) do
    with {:ok, text} <- File.read(data_path),
         {:ok, %{relay: relay}} <- DeviceConfig.parse(text) do
      relay
    else
      _ -> nil
    end
  end

  defp import(text, boot_dir, opts) do
    data_path = Keyword.fetch!(opts, :data_path)

    with {:ok, config} <- DeviceConfig.parse(text),
         :ok <- apply_wifi(config.wifi_networks, Keyword.fetch!(opts, :apply_wifi)),
         :ok <- write_atomically(data_path, text) do
      _ = File.rm(Path.join(boot_dir, @config_file))
      _ = File.rm(Path.join(boot_dir, @error_file))
      {:imported, config}
    else
      {:error, message} -> fail(boot_dir, message)
    end
  end

  defp apply_wifi([], _apply_wifi), do: :ok

  defp apply_wifi(networks, apply_wifi) do
    case apply_wifi.(networks) do
      :ok -> :ok
      {:error, reason} -> {:error, "couldn't apply WiFi settings (#{inspect(reason)})"}
    end
  end

  defp write_atomically(path, contents) do
    tmp_path = path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp_path, contents),
         :ok <- File.rename(tmp_path, path) do
      :ok
    else
      {:error, reason} -> {:error, "couldn't save the settings (#{inspect(reason)})"}
    end
  end

  defp write_sample(boot_dir) do
    path = Path.join(boot_dir, @sample_file)
    sample = DeviceConfig.sample()

    if File.read(path) != {:ok, sample} do
      case File.write(path, sample) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("DeviceConfig: can't write sample: #{inspect(reason)}")
      end
    end
  end

  defp fail(boot_dir, message) do
    explanation = """
    The printer couldn't import #{@config_file}:

      #{message}

    Fix #{@config_file}, then put the SD card back in the Pi and power it on.
    See #{@sample_file} for every setting.
    """

    _ = File.write(Path.join(boot_dir, @error_file), explanation)
    {:error, message}
  end

  defp mount do
    case System.cmd(
           "mount",
           ["-t", "vfat", "-o", "rw,noexec,nodev,nosuid", @autoboot_device, @mount_point],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "mount failed (#{status}): #{String.trim(output)}"}
    end
  end

  defp unmount do
    case System.cmd("umount", [@mount_point], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _status} -> Logger.warning("DeviceConfig: umount failed: #{String.trim(output)}")
    end
  end

  # VintageNet only exists on the device, so it's called dynamically.
  defp apply_vintage_net_wifi(networks) do
    apply(VintageNet, :configure, ["wlan0", DeviceConfig.vintage_net_wifi(networks)])
  end

  defp log_result({:imported, _config} = result) do
    Logger.info("DeviceConfig: imported #{@config_file} from the SD card")
    result
  end

  defp log_result({:error, reason} = result) do
    Logger.error("DeviceConfig: #{@config_file} not imported: #{inspect(reason)}")
    result
  end

  defp log_result(result), do: result
end
