defmodule Vayne.Metric.Mongodb do
  @behaviour Vayne.Task.Metric

  @moduledoc """
  Get Mongodb metrics
  """

  @doc """
  Params below:

  * `hostname`: Mongodb hostname.Required.
  * `port`: Mongodb port. Not required, default 27017.
  * `username`: username. Not required.
  * `password`: password. Not required.
  * `role`: check role, ex: "primary", "secondary", "arbiter". Not required.

  """

  @default_params [database: "admin"]

  def init(params) do
    if Map.has_key?(params, "hostname") do
      role  = Map.get(params, "role")
      params = Enum.reduce(~w(hostname port username password), [], fn (k, acc) ->
        if params[k] do
          Keyword.put(acc, String.to_atom(k), params[k])
        else
          acc
        end
      end)
      params = Keyword.merge(params, @default_params)
      case Mongo.start_link(params) do
        {:ok, conn} -> {:ok, {conn, role}}
        {:error, error} -> {:error, error}
      end
    else
      {:error, "hostname is required"}
    end
  end

  @normal_info_tag ~w(
    asserts
    connections
    globalLock
    network
    opcounters
    opcountersRepl
    backgroundFlushing
  )

  defp wrap_command(conn, params) do
    try do
      Mongo.command(conn, params)
    rescue
      e in DBConnection.ConnectionError -> 
        {:error, "connection error with params: #{inspect params}"}
    end
  end

  def run({conn, role}, log_func) do

    case wrap_command(conn, %{serverStatus: 1}) do
      {:ok, hash} ->
        info_normal = Enum.reduce(@normal_info_tag, %{}, fn (key, acc) ->
          info = get_normal_info(hash[key], key)
          Map.merge(acc, info)
        end)

        info_cursor = get_normal_info(hash["metrics"]["cursor"], "cursor")

        info_extra_info = get_normal_info(hash["extra_info"], "")

        info_mem = hash["mem"]
          |> get_normal_info("mem")
          |> Map.to_list
          |> Enum.map(fn {k, v} -> if k == "mem_bits", do: {k, v}, else: {k, v * 1024 * 1024} end)
          |> Enum.into(%{})

        info_dur = hash["dur"]
          |> get_normal_info("dur")
          |> convert_MB()

        info_lock = hash["locks"]
          |> get_normal_info("locks")
          |> convert_lock_type()

        repl_metric = if is_map(hash["repl"]) do
          get_repl_metrics({conn, role}, log_func, hash["repl"]["me"])
        else
          %{}
        end

        all_info = [info_normal, info_cursor, info_extra_info, info_mem, info_dur, info_lock, repl_metric]

        metrics = all_info
          |> Enum.reduce(fn (info, acc) -> Map.merge(acc, info) end)
          |> cal_connection_percent()
          |> Map.put("mongo.alive", 1)

        {:ok, metrics}

      {:error, error} ->
        log_func.(error)
        {:ok, %{"mongo.alive" => 0}}
    end

  end

  def clean({conn, _role}) do
    #Process.exit(conn, :normal)
    GenServer.stop(conn)
    :ok
  end

  defp get_repl_metrics({conn, role}, log_func, me) do
    case wrap_command(conn, %{replSetGetStatus: 1}) do
      {:error, error} ->
        log_func.(error)
        %{}
      {:ok, repl_metric} ->

        members_role_check = if role != nil do
          find = Enum.find(repl_metric["members"], &(&1["name"] == me))
          stat = if find["stateStr"] == String.upcase(role), do: 1, else: 0
          %{"repl.role_check" => stat}
        else
          %{}
        end

        members_health =
          if Enum.all?(repl_metric["members"], &(&1["health"] == 1)), do: 1, else: 0

        members_role_check
        |> Map.put("repl.members_health", members_health)
        |> Map.put("repl.myState", repl_metric["myState"])
    end
  end

  defp cal_connection_percent(metrics) do

    with {:ok, conn_cur} <- Map.fetch(metrics, "connections_current"),
     {:ok, conn_ava} <- Map.fetch(metrics, "connections_available")
    do
      value = Float.floor(100 * conn_cur / (conn_cur + conn_ava), 2)
      Map.put(metrics, "connections_used_percent", value)
    else
      _ -> metrics
    end
  end

  defp convert_MB(map) do
    map
    |> Map.to_list
    |> Enum.map(fn {k, v} ->
      if k =~ ~r/MB$/ do
        {String.replace(k, ~r/MB$/, "Bytes"), v * 1024 * 1024}
      else
        {k, v}
      end
    end)
    |> Enum.into(%{})
  end

  defp convert_lock_type(type) when is_binary(type) do
    case type do
      "r" -> "ISlock"
      "R" -> "Slock"
      "w" -> "IXlock"
      "W" -> "Xlock"
      _ -> type
    end
  end

  defp convert_lock_type(map) do
    map
    |> Map.to_list
    |> Enum.map(fn {k, v} ->
      case Regex.run(~r/^(.+)_(.+?)$/, k, capture: :all_but_first) do
        [prefix, type] ->
          lock = convert_lock_type(type)
          {"#{prefix}_#{lock}", v}
        _ -> {k, v}
      end
    end)
    |> Enum.into(%{})
  end

  def get_normal_info(hash, prefix) when is_map(hash) do
    keys = Map.keys(hash)
    Enum.reduce(keys, %{}, fn (key, acc) ->
      new_prefix = if prefix != "", do: "#{prefix}_#{key}", else: key
      value = hash[key]
      cond do
        key =~ ~r/^_/ -> acc
        match?(%DateTime{}, value) -> acc
        is_map(value) ->
          map_value = get_normal_info(value, new_prefix)
          Map.merge(acc, map_value)
        is_number(value) -> Map.put(acc, new_prefix, value)
        true             -> acc
      end
    end)
  end
  def get_normal_info(_hash, _prefix), do: %{}

end
