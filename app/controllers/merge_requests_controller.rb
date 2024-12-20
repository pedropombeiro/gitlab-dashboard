# frozen_string_literal: true

class MergeRequestsController < MergeRequestsControllerBase
  delegate :make_full_url, to: :gitlab_client
  helper_method :make_full_url

  def index
    return unless ensure_assignee

    @user = graphql_user(safe_params[:assignee])
    render_404 and return unless @user

    save_current_user(safe_params[:assignee])
    if @user.username != safe_params[:assignee]
      redirect_to merge_requests_path(assignee: @user.username) and return
    end

    response = Services::MergeRequestsCacheService.new.read(safe_params[:assignee])
    @dto = fetch_service.parse_dto(response)

    fresh_when(response)
  end

  def list
    assignee = safe_params.expect(:assignee)
    user = graphql_user(assignee)
    render_404 and return unless user

    save_current_user(assignee)

    response, @dto = Services::GenerateNotificationsService.new(assignee, fetch_service).execute
    if @dto.errors
      return respond_to do |format|
        format.html { render file: Rails.public_path.join("500.html").to_s, layout: false, status: :internal_server_error }
        format.any { head :internal_server_error }
      end
    end

    if Rails.env.production?
      expires_in Services::MergeRequestsCacheService.cache_validity.after(response.updated_at) - Time.current
    end

    respond_to do |format|
      format.html { redirect_to merge_requests_path(assignee: assignee) unless params[:turbo] }
      format.json { render json: response }
    end
  end

  private

  def graphql_user(assignee)
    Rails.cache.fetch(self.class.user_cache_key(assignee), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(assignee)
    end.response.data.user
  end

  def fetch_service
    @fetch_service ||= Services::FetchMergeRequestsService.new(safe_params.expect(:assignee), log_metrics: true)
  end
end
