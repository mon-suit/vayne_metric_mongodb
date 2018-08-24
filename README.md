# vayne_metric_mongodb
[![Build Status](https://travis-ci.org/mon-suit/vayne_metric_mongodb.svg?branch=master)](https://travis-ci.org/mon-suit/vayne_metric_mongodb)

Mongodb metric plugin for [vayne_core](https://github.com/mon-suit/vayne_core) monitor framework.
Checkout real monitor example to see [vayne_server](https://github.com/mon-suit/vayne_server).


## Installation

Add package to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:vayne_metric_mongodb, github: "mon-suit/vayne_metric_mongodb"}
  ]
end
```

## Usage

```elixir
#Setup params for plugin.
params = %{"hostname" => "127.0.0.1"}

#Init plugin.
{:ok, stat} = Vayne.Metric.Mongodb.init(params)

#In fact, log_func will be passed by framework to record error.
log_func = fn msg -> IO.puts msg end

#Run plugin and get returned metrics.
{:ok, metrics} = Vayne.Metric.Mongodb.run(stat, log_func)

#Do with metrics
IO.inspect metrics

#Clean plugin state.
:ok = Vayne.Metric.Mongodb.clean(stat)
```

Support params:

* `hostname`: Mongodb hostname.Required.
* `port`: Mongodb port. Not required, default 27017.
* `username`: username. Not required.
* `password`: password. Not required.
* `role`: check role, ex: "primary", "secondary", "arbiter". Not required.

## Support Metrics

1. All `db.serverStatus()` items(could be parsed to number).
2. Custom items for replica state:
  * `repl.role_check`:  check rs role if set `role` in init. check pass -> 1, other -> 0
  * `repl.members_health`: all `health` in replica members is `1`.
  * `repl.myState`: the replica state of the current instance.
3. Other:
  * `connections_used_percent`: 100 * connections_current / (connections_current + connections_available)
