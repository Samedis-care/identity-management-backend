class Api::V1::User::AppsController < Api::V1::JsonApiController

  MODEL_BASE = Actors::App
  MODEL = ::Actors::App.available
  MODEL_OVERVIEW = ::Actors::App.available
  SERIALIZER = AppSerializer
  OVERVIEW_SERIALIZER = AppSerializer

  SWAGGER = {
    tag: 'Current User'
  }

  undef_method :destroy
  undef_method :create
  undef_method :show

  def index
    super do |records, opts|
      records = records.collect do |app|
        # determine requires_acceptance in app_context
        app.requires_acceptance = current_user.check_acceptances(app.name)
        app
      end
      [records, opts]
    end
  end

  private
  def model_index
    # leave out currently valid tokens from activities
    current_user.apps.order(short_name: 1)
  end

  def cando
    CANDO.merge({
      all: %w(public) # no CANDO required to edit own user info
    })
  end

end
