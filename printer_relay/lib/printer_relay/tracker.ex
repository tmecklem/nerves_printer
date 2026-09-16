if Code.ensure_loaded?(Phoenix.Tracker) do
  defmodule PrinterRelay.Tracker do
    @moduledoc false
    use Phoenix.Tracker

    @topic "printer_relay:printers"
    @changes_topic "printer_relay:printers_changed"

    def start_link(pubsub) do
      Phoenix.Tracker.start_link(__MODULE__, [pubsub_server: pubsub],
        name: __MODULE__,
        pubsub_server: pubsub
      )
    end

    def track(pid, printer_id, meta) do
      meta = Map.merge(meta, %{pid: pid, connected_at: System.system_time(:microsecond)})
      Phoenix.Tracker.track(__MODULE__, pid, @topic, printer_id, meta)
    end

    def update(pid, printer_id, changes) do
      Phoenix.Tracker.update(__MODULE__, pid, @topic, printer_id, &Map.merge(&1, changes))
    end

    def subscribe do
      Phoenix.PubSub.subscribe(:persistent_term.get({__MODULE__, :pubsub}), @changes_topic)
    end

    def lookup(printer_id) do
      __MODULE__
      |> Phoenix.Tracker.get_by_key(@topic, printer_id)
      |> Enum.map(fn {_pid, meta} -> meta end)
      |> Enum.max_by(& &1.connected_at, fn -> nil end)
    end

    def printers do
      __MODULE__
      |> Phoenix.Tracker.list(@topic)
      |> Enum.group_by(fn {id, _meta} -> id end, fn {_id, meta} -> meta end)
      |> Enum.map(fn {id, metas} ->
        metas
        |> Enum.max_by(& &1.connected_at)
        |> Map.take([:online, :model, :client_version, :connected_at])
        |> Map.put(:id, id)
      end)
      |> Enum.sort_by(& &1.connected_at)
    end

    @impl Phoenix.Tracker
    def init(opts) do
      pubsub = Keyword.fetch!(opts, :pubsub_server)
      :persistent_term.put({__MODULE__, :pubsub}, pubsub)
      {:ok, %{pubsub_server: pubsub}}
    end

    # Every node's tracker sees every diff, so each notifies only its own subscribers.
    @impl Phoenix.Tracker
    def handle_diff(diff, state) do
      if Map.has_key?(diff, @topic) do
        Phoenix.PubSub.local_broadcast(
          state.pubsub_server,
          @changes_topic,
          {:printer_relay, :printers_changed}
        )
      end

      {:ok, state}
    end
  end
end
