module MergeRequestsPipelineHelper
  include ActionView::Helpers::TagHelper

  def pipeline_failure_summary(pipeline)
    failed_jobs = pipeline.failedJobs
    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }

    header = "#{pluralize(failed_jobs.count, "job")} #{pluralize_without_count(failed_jobs.count, "has", "have")} failed in the pipeline:"

    if failed_job_traces.count == 1
      failed_job_trace = failed_job_traces.first

      [
        "#{header} #{tag.code(failed_job_trace.name, escape: false)}",
        failed_job_trace.trace.htmlSummary
      ].join("<br/>")
    elsif failed_jobs.count.positive?
      <<~HTML
        #{header}<br/><br/>
        #{tag.ul(failed_jobs.nodes.map { |j| tag.li(tag.code(j.name)) }.join, escape: false)}
      HTML
    end
  end

  def pipeline_summary(pipeline)
    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }

    summary = nil
    if failed_job_traces.count <= 1 && pipeline.status == "RUNNING"
      summary = "#{pluralize(pipeline.runningJobs.count, "job")} still running"
    end

    summary ||= pipeline_failure_summary(pipeline) if pipeline.status == "FAILED"

    summary
  end

  def pipeline_web_url(pipeline)
    return unless pipeline.path

    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }
    web_path = pipeline.path

    # Try to make the user land in the most contextual page possible, depending on the state of the pipeline
    if failed_job_traces.count > 1
      web_path += "/failures"
    else
      case pipeline.status
      when "RUNNING"
        web_path = (pipeline.runningJobs.count == 1) ? pipeline.firstRunningJob.nodes.first.webPath : "#{web_path}/builds"
      when "FAILED"
        web_path = (failed_job_traces.count == 1) ? failed_job_traces.first.webPath : "#{web_path}/failures"
      end
    end

    make_full_url(web_path)
  end
end
