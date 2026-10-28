require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3555. A placeholder written as "% {email}"
# (a space after the %, often from machine translation splitting the token) does not match
# I18n's interpolation pattern, so the user reads the placeholder text instead of the value.
RSpec.describe 'locale interpolation placeholders' do # rubocop:disable RSpec/DescribeClass -- covers YAML data, no class under test
  def leaf_strings(node, path = [], &block)
    case node
    when Hash then node.each { |key, value| leaf_strings(value, path + [key], &block) }
    when String then yield path.join('.'), node
    end
  end

  Dir[Rails.root.join('config/locales/*.yml')].each do |file|
    it "has no placeholder split by whitespace in #{File.basename(file)}" do
      broken = []
      leaf_strings(YAML.load_file(file)) do |key, value|
        broken << key if value.match?(/%\s+\{\w+\}/)
      end

      expect(broken).to be_empty
    end
  end

  %w[fr ru].each do |locale|
    it "interpolates the e-mail address in #{locale} devise.mailer.account_confirm_resend" do
      text = I18n.t('devise.mailer.account_confirm_resend', email: 'jane@example.com', locale: locale)

      expect(text).to include('(jane@example.com)')
    end
  end

  it 'interpolates the new address as link text in fr devise.mailer.email_change.message_html' do
    text = I18n.t('devise.mailer.email_change.message_html',
                  email_new: 'jane@example.com', support_email: 'help@example.com', locale: :fr)

    expect(text).to include('<a href="mailto:jane@example.com">jane@example.com </a>')
  end
end
