module SetLocale
  extend ActiveSupport::Concern

  private
  def set_locale
    # Remove inappropriate/unnecessary ones
    _set_locale = begin
      params[:locale] ||                                     # Request parameter
      extract_locale_from_accept_language_header ||          # Language header - app sent/browser config
      (current_user.get_locale unless current_user.nil?) ||  # Model saved configuration
      I18n.default_locale                                    # english by Rails-default
    end
    # cleanup region part of requested locale unless available
    _set_locale = _set_locale.to_s.split('_').first unless I18n.available_locales.include?(_set_locale.to_sym)
    _set_locale = I18n.default_locale unless I18n.available_locales.include?(_set_locale.to_sym)
    I18n.locale = _set_locale
  end

  # Extract language from request header
  def extract_locale_from_accept_language_header
    request.env['HTTP_ACCEPT_LANGUAGE'].scan(/^[a-z]{2}/).first&.to_sym if request.env['HTTP_ACCEPT_LANGUAGE']
  end

end
