# frozen_string_literal: true

class MergeRequestsController < MergeRequestsControllerBase
  include Honeybadger::InstrumentationHelper

  def index
    if safe_params[:assignee].present?
      validated_assignee = validate_username(safe_params[:assignee])
      if validated_assignee
        return redirect_to merge_requests_path(author: validated_assignee, referrer: safe_params[:referrer])
      else
        render_404 and return
      end
    end

    return unless ensure_author

    @user = graphql_user(author)
    render_404 and return unless @user

    if @user.username != safe_params[:author]
      redirect_to merge_requests_path(author: @user.username) and return
    end

    handle_visit

    save_current_user(author) if safe_params.exclude?(:referrer)

    response = MergeRequestsCacheService.new.read(author, :open)
    fetch_service = FetchMergeRequestsService.new(author)
    @dto = fetch_service.parse_dto(response, :open)

    fresh_when(response)
  end

  def legacy_index
    redirect_to merge_requests_path(**safe_params)
  end

  def open_list
    handle_merge_requests_list(:open)
  end

  def merged_list
    handle_merge_requests_list(:merged)
  end

  def merged_chart
    author = safe_params.expect(:author)
    user = graphql_user(author)
    render_404 and return unless user

    save_current_user(safe_params[:author]) if safe_params.exclude?(:referrer)
  end

  private

  def graphql_user(username)
    Rails.cache.fetch(self.class.user_cache_key(username), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(username)
    end.response.data.user
  end

  def handle_visit
    metric_source "custom_metrics"
    metric_attributes(
      username: author,
      referrer: safe_params[:referrer],
      path: request.path,
      request_ip: request.remote_ip
    )
    increment_counter("user.visit")
  end

  def handle_merge_requests_list(type)
    author = safe_params.expect(:author)
    user = graphql_user(author)
    render_404 and return unless user

    handle_visit

    fetch_service = FetchMergeRequestsService.new(author)
    if safe_params.include?(:referrer)
      result = fetch_service.execute(type)
      response = result.response
      @dto = fetch_service.parse_dto(response, type)
    else
      save_current_user(author)

      response, @dto = GenerateNotificationsService.new(@current_user, type, fetch_service).execute
    end

    if Rails.env.production?
      expires_in MergeRequestsCacheService.cache_validity.after(response.updated_at) - Time.current
    end

    respond_to do |format|
      format.html
      format.json { render json: response }
    end
  end
end
