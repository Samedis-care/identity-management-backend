class ApplicationMailer < ActionMailer::Base
  default from: 'no-reply@ident.services'
  layout 'mailer'

  DEFAULT_HEADERS ||= {
    'Precedence'=> 'Bulk',
    'X-Auto-Response-Suppress' => 'All'
  }

  def self.default_headers
    self::DEFAULT_HEADERS
  end

  def default_headers
    self.class.default_headers
  end

  def mail(headers = {}, &block)
    return super unless (app.config.try(:mailer).try(:smtp_settings) rescue nil)

    headers[:delivery_method_options] = ActionMailer::Base.smtp_settings.merge(app.config.mailer.smtp_settings.delivery_method_options)
    super
  end
end
