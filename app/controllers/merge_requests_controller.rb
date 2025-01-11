# frozen_string_literal: true

class MergeRequestsController < MergeRequestsControllerBase
  delegate :make_full_url, to: :gitlab_client
  helper_method :make_full_url

  def index
    return unless ensure_assignee

    @user = graphql_user(assignee)
    render_404 and return unless @user

    if @user.username != safe_params[:assignee]
      redirect_to merge_requests_path(assignee: @user.username) and return
    end

    save_current_user(safe_params[:assignee])
    response = MergeRequestsCacheService.new.read(safe_params[:assignee], :open)
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
    assignee = safe_params.expect(:assignee)
    user = graphql_user(assignee)
    render_404 and return unless user

    save_current_user(assignee)
  end

  private

  def graphql_user(assignee)
    Rails.cache.fetch(self.class.user_cache_key(assignee), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(assignee)
    end.response.data.user
  end

  def fetch_service
    @fetch_service ||= FetchMergeRequestsService.new(safe_params.expect(:assignee), request_ip: request.remote_ip)
  end

  def handle_merge_requests_list(type)
    assignee = safe_params.expect(:assignee)
    user = graphql_user(assignee)
    render_404 and return unless user

    save_current_user(assignee)

    response, @dto = GenerateNotificationsService.new(@current_user, type, fetch_service).execute

    if Rails.env.production?
      expires_in MergeRequestsCacheService.cache_validity.after(response.updated_at) - Time.current
    end

    respond_to do |format|
      format.html
      format.json { render json: response }
    end
  end
end
