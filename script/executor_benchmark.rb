# frozen_string_literal: true

# Run with: bin/rails runner script/executor_benchmark.rb

# Load Action View so view_component registers its executor hook.
ActionView::Base

# Count how many times a file watcher checks the files for changes.
checks = Concurrent::AtomicFixnum.new
ActiveSupport::FileUpdateChecker.prepend(Module.new do
  define_method(:execute_if_updated) do |*args, &block|
    checks.increment
    super(*args, &block)
  end
end)

# Post 50 jobs to Action Cable's worker pool and measure the time until all of
# them have finished. This is what Action Cable does for every broadcast
# message: a stream handler posts a job with `worker_pool.async_invoke`, and
# the worker pool wraps the job in the executor before running it. That is
# where view_component checks the templates.
#
# A real job transmits the message to the browser. The job here only counts
# down a latch, so the measured time is the cost of the executor hooks.
jobs = 50
done = Concurrent::CountDownLatch.new(jobs)
handler = ->(_message) { done.count_down }
worker_pool = ActionCable.server.worker_pool

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
jobs.times { |i| worker_pool.async_invoke(handler, :call, "chunk #{i}", connection: nil) }
done.wait
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

puts "view_component #{ViewComponent::VERSION::STRING}"
puts "Action Cable worker pool (#{ActionCable.server.config.worker_pool_size} threads)"
puts "  jobs: #{jobs}"
puts "  FileUpdateChecker#execute_if_updated calls: #{checks.value}"
puts "  total: %.1fms" % (elapsed * 1000)
