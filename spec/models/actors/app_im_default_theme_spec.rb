require 'rails_helper'

# The identity-management app gets the light theme of the IM frontend
# (src/theme.ts) as its login look when it is created (ensure_im_app!). Nothing is saved here: the test database already
# holds the IM app, so creation itself cannot be exercised without deleting it.
RSpec.describe Actors::App do
  describe '.im_default_theme' do
    subject(:theme) { described_class.im_default_theme }

    it 'is the light theme of the IM frontend' do
      expect(theme.mode).to eq('light')
      expect(theme.primary.main).to eq('#00788A')
      expect(theme.secondary.main).to eq('#002D50')
      expect(theme.background.default).to eq('#FFFFFF')
      expect(theme.background.advanced)
        .to eq('linear-gradient(270deg, #00AFC3 0%, #0869B3 60%, #0A4F86 100%)')
      expect(theme.components_care.ui_kit.action_button.background_color).to eq('#00788A')
    end

    it 'clears the field defaults it does not set' do
      expect(theme.primary.light).to be_nil
      expect(theme.primary.dark).to be_nil
      expect(theme.secondary.light).to be_nil
      expect(theme.secondary.dark).to be_nil
    end

    it 'fits into an app config' do
      app = described_class.new
      app.config.theme = theme
      expect(app.config.theme.primary.main).to eq('#00788A')
      expect(app.config.theme.components_care.ui_kit.action_button.background_color).to eq('#00788A')
    end

    it 'returns a fresh document every time' do
      expect(described_class.im_default_theme).not_to equal(described_class.im_default_theme)
    end
  end
end
