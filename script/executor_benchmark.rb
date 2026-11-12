# frozen_string_literal: true

# Run with: bin/rails runner script/executor_benchmark.rb
#
# 1. Measures an empty `executor.wrap`. The block is empty, so the time is the
#    cost of the executor hooks. New threads are used because the runner's main
#    thread is already inside the executor.
# 2. Posts jobs to Action Cable's worker pool, the same way a stream handler
#    does for every broadcast message (`worker_pool.async_invoke`). Action Cable
#    wraps each job in the executor.

ActionView::Base # load Action View so view_component registers its executor hook

checks = Concurrent::AtomicFixnum.new
ActiveSupport::FileUpdateChecker.prepend(Module.new do
  define_method(:execute_if_updated) do |*args, &block|
    checks.increment
    super(*args, &block)
  end
end)

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def measure_executor(threads:, runs:)
  times = Array.new(threads) do
    Thread.new do
      Array.new(runs) do
        started = now
        Rails.application.executor.wrap { }
        now - started
      end
    end
  end.flat_map(&:value)

  times.sum / times.size * 1000
end

puts "view_component #{ViewComponent::VERSION::STRING}"
puts

runs = 20
single = measure_executor(threads: 1, runs: runs)
four = measure_executor(threads: 4, runs: runs)

puts "Empty executor.wrap"
puts "  executor runs: #{runs + 4 * runs}"
puts "  FileUpdateChecker#execute_if_updated calls: #{checks.value}"
puts "  1 thread:  %.2fms per run" % single
puts "  4 threads: %.2fms per run" % four
puts

checks.value = 0
jobs = 50
done = Concurrent::CountDownLatch.new(jobs)
handler = ->(_message) { done.count_down } # stands in for transmitting to the browser
worker_pool = ActionCable.server.worker_pool

started = now
jobs.times { |i| worker_pool.async_invoke(handler, :call, "chunk #{i}", connection: nil) }
done.wait
elapsed = now - started

puts "Action Cable worker pool (#{ActionCable.server.config.worker_pool_size} threads)"
puts "  jobs: #{jobs}"
puts "  FileUpdateChecker#execute_if_updated calls: #{checks.value}"
puts "  total: %.2fs" % elapsed
