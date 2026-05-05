require "get_process_mem"
require "objspace"

ITERATIONS = ENV.fetch("PROFILE_ITERATIONS", 20).to_i
JOB_NAME = ENV.fetch("PROFILE_JOB", "all")

ALL_JOBS = {
  "schedule_cache_refresh" => -> { ScheduleCacheRefreshJob.perform_now },
  "send_metrics" => -> { SendMetricsJob.perform_now },
  "merge_requests_fetch" => -> {
    user = GitlabUser.first
    MergeRequestsFetchJob.perform_now(user.username, :open) if user
  }
}.freeze

JOBS = if JOB_NAME == "all"
  ALL_JOBS.values
else
  [ALL_JOBS.fetch(JOB_NAME)]
end

def rss_mb
  GetProcessMem.new.mb
end

def object_counts
  counts = Hash.new(0)
  class_of = Object.instance_method(:class)
  ObjectSpace.each_object { |o| counts[class_of.bind_call(o)] += 1 }
  counts.sort_by { |_, v| -v }.first(30).to_h
end

def gc_stats
  s = GC.stat
  {count: s[:count], heap_live_slots: s[:heap_live_slots], heap_free_slots: s[:heap_free_slots]}
end

def print_separator
  puts "-" * 70
end

def print_snapshot(label, rss, counts, gc)
  puts "\n=== #{label} ==="
  puts "RSS: #{rss.round(1)} MB"
  puts "GC:  count=#{gc[:count]}  live_slots=#{gc[:heap_live_slots]}  free_slots=#{gc[:heap_free_slots]}"
  puts "Top object counts:"
  counts.each { |klass, n| puts "  #{klass.name.to_s.ljust(50)} #{n}" }
end

def compact_and_report(label)
  before = GC.stat[:heap_live_slots]
  GC.compact
  after = GC.stat[:heap_live_slots]
  puts "  [#{label}] GC.compact: live_slots #{before} -> #{after} (freed #{before - after})"
end

print_separator
puts "SolidQueue job memory profiler"
puts "Job: #{JOB_NAME}  Iterations: #{ITERATIONS}"
puts "PID: #{Process.pid}  Ruby: #{RUBY_VERSION}"
print_separator

GC.start(full_mark: true, immediate_sweep: true)
compact_and_report("baseline")

baseline_rss = rss_mb
baseline_counts = object_counts
baseline_gc = gc_stats
print_snapshot("baseline", baseline_rss, baseline_counts, baseline_gc)

rss_history = [baseline_rss]

ITERATIONS.times do |i|
  JOBS.each do |job|
    job.call
  rescue => e
    puts "  [iteration #{i + 1}] job raised #{e.class}: #{e.message.lines.first.chomp}"
  end

  GC.start(full_mark: true, immediate_sweep: true)
  current_rss = rss_mb
  current_counts = object_counts
  current_gc = gc_stats
  rss_history << current_rss

  growth = current_rss - baseline_rss
  step = current_rss - rss_history[-2]

  puts "\n=== iteration #{i + 1}/#{ITERATIONS} ==="
  growth_sign = (growth >= 0) ? "+" : ""
  step_sign = (step >= 0) ? "+" : ""
  puts "RSS: #{current_rss.round(1)} MB  (#{growth_sign}#{growth.round(1)} MB from baseline, #{step_sign}#{step.round(1)} MB from last)"
  puts "GC:  count=#{current_gc[:count]}  live_slots=#{current_gc[:heap_live_slots]}  free_slots=#{current_gc[:heap_free_slots]}"

  new_objects = current_counts.filter_map do |klass, n|
    diff = n - (baseline_counts[klass] || 0)
    [klass, n, diff] if diff > 50
  end.sort_by { |_, _, d| -d }.first(15)

  if new_objects.any?
    puts "Object growth vs baseline (>50 new):"
    new_objects.each { |klass, n, diff| puts "  #{klass.name.to_s.ljust(50)} #{n}  (+#{diff})" }
  end
end

print_separator
puts "\nSummary"
puts "RSS history (MB): #{rss_history.map { |r| r.round(1) }.join(" -> ")}"
total_growth = rss_history.last - rss_history.first
total_sign = (total_growth >= 0) ? "+" : ""
puts "Total growth: #{total_sign}#{total_growth.round(1)} MB over #{ITERATIONS} iterations"
puts "Average growth per iteration: #{(total_growth / ITERATIONS).round(2)} MB"

compact_and_report("final")
final_rss = rss_mb
puts "RSS after final GC.compact: #{final_rss.round(1)} MB"
puts "Retained (non-reclaimable) growth: #{(final_rss - baseline_rss).round(1)} MB"
print_separator
