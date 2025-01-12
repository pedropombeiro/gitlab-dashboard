# frozen_string_literal: true

class MergeRequestsController < MergeRequestsControllerBase
  delegate :make_full_url, to: :gitlab_client
  helper_method :make_full_url

  def index
    return unless ensure_author

    @user = graphql_user(author)
    render_404 and return unless @user

    if @user.username != safe_params[:author]
      redirect_to merge_requests_path(author: @user.username) and return
    end

    save_current_user(safe_params[:author])
    response = MergeRequestsCacheService.new.read(safe_params[:author], :open)
    fetch_service = FetchMergeRequestsService.new(safe_params[:author], request_ip: request.remote_ip)
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

    save_current_user(author)
  end

  private

  def graphql_user(username)
    Rails.cache.fetch(self.class.user_cache_key(username), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(username)
    end.response.data.user
  end

  def handle_merge_requests_list(type)
    author = safe_params.expect(:author)
    user = graphql_user(author)
    render_404 and return unless user

    save_current_user(author)

    fetch_service = FetchMergeRequestsService.new(author, request_ip: request.remote_ip)
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
