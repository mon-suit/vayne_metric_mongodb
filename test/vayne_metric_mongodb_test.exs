defmodule Vayne.Metric.MongodbTest do
  use ExUnit.Case, async: false

  require IEx

  @supervisor Vayne.Test.TaskSupervisor

  setup_all do
    :inet_gethost_native.start_link
    Task.Supervisor.start_link(name: @supervisor)
    Process.sleep(1_000)
    :ok
  end

  setup do
    port_count    = length(Port.list())
    ets_count     = length(:ets.all())
    process_count = length(Process.list())
    on_exit "ensure release resource", fn ->
      Process.sleep(1_000)
      assert process_count == length(Process.list())
      assert port_count    == length(Port.list())
      assert ets_count     == length(:ets.all())
    end
  end

  @suc_params %{"hostname" => "127.0.0.1"}
  @fail_params %{"hostname" => "127.0.0.1", "port" => 3333}

  test "normal success" do

    task = %Vayne.Task{
      uniqe_key:   "normal success",
      interval:    10,
      metric_info: %{module: Vayne.Metric.Mongodb, params: @suc_params},
      export_info:   %{module: Vayne.Export.Console, params: nil}
    }

    async = Task.Supervisor.async_nolink(@supervisor, fn ->
      Vayne.Task.test_task(task)
    end)

    {:ok, metrics} = Task.await(async)
    assert Map.keys(metrics) > 0
  end

  test "error port" do
    task = %Vayne.Task{
      uniqe_key:   "error port",
      interval:    10,
      metric_info: %{module: Vayne.Metric.Mongodb, params: @fail_params},
      export_info:   %{module: Vayne.Export.Console, params: nil}
    }

    async = Task.Supervisor.async_nolink(@supervisor, fn ->
      Vayne.Task.test_task(task)
    end)

    assert {:ok, %{"mongo.alive" => 0}} = Task.await(async, :infinity)
  end


  test "connect other server, connection will down" do
    Process.flag(:trap_exit, true)

    [
      %{"hostname" => "127.0.0.1", "port" => 3306},
      %{"hostname" => "127.0.0.1", "port" => 6379},
      %{"hostname" => "127.0.0.1", "port" => 11211},
    ]
    |> Enum.each(fn param ->

      task = %Vayne.Task{
        uniqe_key:   "connect other server port #{param["port"]}",
        interval:    10,
        metric_info: %{module: Vayne.Metric.Mongodb, params: param},
        export_info:   %{module: Vayne.Export.Console, params: nil}
      }

      _async = Task.Supervisor.async_nolink(@supervisor, fn ->
        Vayne.Task.test_task(task)
      end)

      msg = receive do
        msg -> msg
      end
      assert {:DOWN, _ref, _, _pid, _msg} = msg
    end)
  end


end
