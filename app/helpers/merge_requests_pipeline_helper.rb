module MergeRequestsPipelineHelper
  include ActionView::Helpers::TagHelper

  def pipeline_status(pipeline)
    status = pipeline.status

    if status == "RUNNING"
      "#{humanized_enum(status)} (#{pipeline.finishedJobs.count.to_i * 100 / pipeline.jobs.count.to_i}%)"
    else
      humanized_enum(status)
    end
  end

  def pipeline_failure_summary(pipeline)
    failed_jobs = pipeline.failedJobs
    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }

    header = "#{pluralize(failed_jobs.count, "job")} #{pluralize_without_count(failed_jobs.count, "has", "have")} failed in the pipeline:"

    if failed_job_traces.one?
      failed_job_trace = failed_job_traces.sole

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
    if !failed_job_traces.many? && pipeline.status == "RUNNING"
      summary = "#{pluralize(pipeline.runningJobs.count, "job")} still running"
    end

    summary ||= pipeline_failure_summary(pipeline) if pipeline.status == "FAILED"

    summary
  end

  def pipeline_web_url(pipeline, focus_on_failed = false)
    return unless pipeline.path

    failed_jobs = pipeline.failedJobs
    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }.presence
    failed_job_traces ||= pipeline.failedJobTraces.nodes

    web_path = pipeline.path

    # Try to make the user land in the most contextual page possible, depending on the state of the pipeline
    if failed_job_traces.one?
      case pipeline.status
      when "RUNNING"
        web_path =
          if focus_on_failed
            failed_job_web_path(failed_job_traces.sole)
          else
            (pipeline.runningJobs.count == 1) ? pipeline.runningJobs.nodes.sole.webPath : "#{web_path}/builds"
          end
      when "FAILED"
        web_path = failed_job_web_path(failed_job_traces.sole)
      end
    elsif failed_jobs.count.positive?
      web_path += "/failures"
    elsif pipeline.status == "RUNNING" && pipeline.runningJobs.count == 1
      web_path = pipeline.runningJobs.nodes.sole.webPath
    end

    make_full_url(web_path)
  end

  private

  def failed_job_web_path(failed_job_trace)
    if failed_job_trace.downstreamPipeline&.jobs&.nodes&.one?
      failed_job_trace.downstreamPipeline.jobs.nodes.sole.webPath
    else
      failed_job_trace.webPath
    end
  end
end
