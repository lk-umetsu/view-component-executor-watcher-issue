# view-component-executor-watcher-issue

Reproduction for a view_component issue: the template watcher runs on every executor run, slowing Action Cable broadcasts when template caching is off.

## What this shows

Since view_component 4.17.0, the engine checks the component templates for changes in an `app.executor.to_run` hook. With the default `ActiveSupport::FileUpdateChecker`, every executor run globs the autoload paths and stats every template.

Action Cable wraps each worker job in `app.executor.wrap`, so every broadcast transmission pays this cost. It is large when the app lives on a filesystem where `stat` is slow, such as a Docker Desktop for Mac bind mount.

## How to run

The app is a `rails new --minimal` app with view_component added. `compose.yaml` bind-mounts this directory into the container, so the app runs on the slow filesystem.

```sh
VC_VERSION=4.15.0 docker compose run --rm app
VC_VERSION=4.23.0 docker compose run --rm app
```

Each run does the following (`bin/benchmark`):

1. Installs the gems for the given view_component version.
2. Runs `script/executor_benchmark.rb`, which measures two things:
   - An empty `Rails.application.executor.wrap { }`. The block is empty, so the time is the cost of the executor hooks.
   - 50 jobs posted to Action Cable's worker pool with `worker_pool.async_invoke`. This is [what a stream handler does for every broadcast message](https://github.com/rails/rails/blob/40179933e3c89626291a29b6e1a7f9b726d55e19/actioncable/lib/action_cable/channel/streams.rb#L163-L169), and [Action Cable wraps each job in the executor](https://github.com/rails/rails/blob/40179933e3c89626291a29b6e1a7f9b726d55e19/actioncable/lib/action_cable/engine.rb#L74-L84). The jobs do nothing, so no browser or WebSocket is needed.

To look like a mid-sized app, the repository contains 250 components (`.rb` and `.html.erb`) under `app/components/generated` and 500 models under `app/models/generated`. They were created with `ruby script/generate_files.rb`. To try other sizes, run it again with `COMPONENTS` and `MODELS`.

## Results

Docker Desktop 4.99.0 for Mac (Apple silicon), Apple Virtualization framework, VirtioFS:

```
view_component 4.15.0

Empty executor.wrap
  executor runs: 100
  FileUpdateChecker#execute_if_updated calls: 0
  1 thread:  0.04ms per run
  4 threads: 0.01ms per run

Action Cable worker pool (4 threads)
  jobs: 50
  FileUpdateChecker#execute_if_updated calls: 0
  total: 0.00s
```

```
view_component 4.23.0

Empty executor.wrap
  executor runs: 100
  FileUpdateChecker#execute_if_updated calls: 100
  1 thread:  45.94ms per run
  4 threads: 125.84ms per run

Action Cable worker pool (4 threads)
  jobs: 50
  FileUpdateChecker#execute_if_updated calls: 50
  total: 1.55s
```

With 4.23.0, broadcasting 50 messages to one subscriber takes about 1.5 seconds longer, even though the jobs themselves do nothing.

On a fast filesystem the time per run is much smaller, but the check still runs once per executor run.
