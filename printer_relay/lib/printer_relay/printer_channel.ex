if Code.ensure_loaded?(Phoenix.Channel) do
  defmodule PrinterRelay.PrinterChannel do
    @moduledoc false
    use Phoenix.Channel

    require Logger

    alias PrinterRelay.Tracker

    @protocol 1

    @impl Phoenix.Channel
    def join("printer_relay:printer:" <> printer_id, params, socket) do
      cond do
        printer_id != socket.assigns.printer_relay_id ->
          {:error, %{reason: "unauthorized"}}

        params["protocol"] != @protocol ->
          {:error, %{reason: "unsupported_protocol"}}

        true ->
          meta = %{
            online: params["online"] == true,
            model: params["model"],
            client_version: params["client_version"]
          }

          {:ok, _ref} = Tracker.track(self(), printer_id, meta)
          {:ok, assign(socket, :jobs, %{})}
      end
    end

    @impl Phoenix.Channel
    def handle_info({:printer_relay_print, reply_to, zpl}, socket) do
      job_id = Integer.to_string(System.unique_integer([:positive]))
      push(socket, "print", %{"job_id" => job_id, "zpl" => zpl})
      {:noreply, update_in(socket.assigns.jobs, &Map.put(&1, job_id, reply_to))}
    end

    @impl Phoenix.Channel
    def handle_in("print_result", %{"job_id" => job_id} = result, socket) do
      {reply_to, jobs} = Map.pop(socket.assigns.jobs, job_id)

      if reply_to do
        send(reply_to, {reply_to, to_result(result)})
      else
        Logger.warning("PrinterRelay: result for unknown job #{inspect(job_id)}")
      end

      {:noreply, assign(socket, :jobs, jobs)}
    end

    def handle_in("status", params, socket) do
      changes = %{online: params["online"] == true, model: params["model"]}
      {:ok, _ref} = Tracker.update(self(), socket.assigns.printer_relay_id, changes)
      {:reply, :ok, socket}
    end

    defp to_result(%{"ok" => true}), do: :ok
    defp to_result(result), do: {:error, {:printer, to_string(result["error"])}}
  end
end
