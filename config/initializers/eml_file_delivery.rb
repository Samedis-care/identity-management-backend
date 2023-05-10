require 'mail'

class EmlFileDelivery
  attr_accessor :settings

  def initialize(settings)
    self.settings = settings
  end

  def deliver!(mail)
    recipient = mail.destinations.first
    timestamp = Time.now.strftime('%Y%m%d%H%M%S')
    file_name = "#{recipient}-#{timestamp}.eml"
    file_path = File.join(settings[:location]||Rails.root.join('tmp', 'mails'), file_name)
    File.open(file_path, 'w') do |f|
      f.write(mail.to_s)
    end
  end
end

ActionMailer::Base.add_delivery_method :eml_file, EmlFileDelivery
