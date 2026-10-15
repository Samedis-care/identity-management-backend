require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2724. In production the json_api.* strings
# are the ENTIRE message body of the JSON:API error response (BaseControllerMethods), read by a client
# as a standalone sentence: ru record_not_found_error / database_error and fr database_error were
# lowercase while every neighbouring key and every other locale was capitalized.
RSpec.describe 'json_api locale strings' do
  %w[en de fr nl ru].each do |locale|
    describe locale do
      let(:strings) do
        YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).dig(locale, 'json_api').select { |_key, value| value.is_a?(String) }
      end

      it 'has the json_api block' do
        expect(strings).not_to be_empty
      end

      it 'starts every message with an uppercase letter' do
        lowercase = strings.reject { |_key, value| value.lstrip.match?(/\A\p{Lu}/) }

        expect(lowercase.keys).to be_empty
      end
    end
  end

  it 'has the same keys in every locale, so none is missing a capitalized translation' do
    keys = %w[en de fr nl ru].to_h { |locale| [locale, YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).dig(locale, 'json_api').keys.sort] }

    expect(keys.values.uniq.size).to eq(1)
  end
end
