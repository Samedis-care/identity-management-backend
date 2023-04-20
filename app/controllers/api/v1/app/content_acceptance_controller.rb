class Api::V1::App::ContentAcceptanceController < Api::V1::JsonApiController

  MODEL_BASE = Content
  MODEL = Content
  #MODEL_OVERVIEW = Content
  SERIALIZER = ContentAcceptanceSerializer
  #OVERVIEW_SERIALIZER = ContentSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  skip_before_action :authenticate_user!, only: :show
  skip_before_action :authorize, only: :show

  undef_method :index
  undef_method :destroy

  def show
    if (current_user.present? rescue false)
      current_user.app_context = current_app
    else
    end
    record = Content.where(app: current_app, active: true)
                    .where(name: params_json_api[:name])
                    .order({ version: -1 }).first
    if record.present?
      record.user = current_user if (current_user.present? rescue false)
    else
      msg = "record: #{record.inspect} / current_app: #{current_app} / name: #{params_json_api[:name]}"
      render_jsonapi_error(404, msg, 404) and return
    end
    render_serialized_record(record: record)
  end

  def update
    current_user.app_context = params_json_api[:app]
    current_user.invite_token = params[:invite_token]
    content_to_accept = Content.where(app: current_user.app_context)
                               .where(active: true, acceptance_required: true)
                               .where(_id: params_json_api[:id]).first
    if content_to_accept
      success = current_user.accept_content!(content_to_accept)
    else
      # nothing to accept, all good
      success = true
    end
    outstanding_acceptances = current_user.check_acceptances

    current_user.redirect_host = params[:redirect_host]
    current_user.redirect_path = params[:redirect_host]
    url_values = {
      HOST: current_user.host,
      APP: current_user.app_context,
      TOKEN: current_token.token,
      REFRESH_TOKEN: current_token.refresh_token,
      REDIRECT_PATH: current_user.redirect_path,
      TOKEN_EXPIRE: current_token.expires_in.seconds.from_now.to_i*1000,
      INVITE_TOKEN: current_user.invite_token
    }
    if outstanding_acceptances.any?
      url = current_user.redirect_url_acceptance(url_values.merge({
        HOST: User.host('identity-management'),
        NAME: outstanding_acceptances.first,
        INVITE_TOKEN: current_user.invite_token
      }))
    else
      url = current_user.redirect_url_authenticated(url_values)
    end
    render_jsonapi_msg({ success: success }, 200, { redirect_url: url })
  end

  private
  def cando
    CANDO.merge({
      show: %w(public),
      update: %w(public)
    })
  end

end
