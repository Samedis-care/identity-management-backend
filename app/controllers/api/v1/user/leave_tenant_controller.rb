class Api::V1::User::LeaveTenantController < Api::V1::JsonApiController
  MODEL_BASE = Actors::Mapping
  MODEL = -> { Actors::Tenant.find(params[:id]).descendants.mappings }
  MODEL_OVERVIEW = MODEL
  SERIALIZER = nil
  OVERVIEW_SERIALIZER = nil

  undef_method :index
  undef_method :show
  undef_method :create
  undef_method :update

  def destroy
    records = records_destroy

    records.delete_all
    current_user.cache_expire!

    success = records_destroy.none?

    render_jsonapi_msg({
      success:,
      error: (success ? nil : :leaving_tenant_failed),
      message: success ? nil : I18n.t('errors.user.leaving_tenant_failed')
    }, (success ? 200 : 409))
  end

  private

  def records_destroy
    model_destroy.where(user_id: current_user.id)
  end

  def cando
    CANDO.merge({
      destroy: %w(public)
    })
  end
  # end
end
