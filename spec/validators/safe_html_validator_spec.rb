require 'rails_helper'

# Ported from samedis-care-backend's identical spec (issue #2417). This
# backend independently feeds the same downstream chain -- a Tenant's name
# here is echoed back to samedis-care-backend's Tenant#handle field, which
# that repo's PR #4126 established is otherwise unvalidated on that end.
RSpec.describe SafeHtmlValidator do
  let(:model_class) do
    Class.new do
      include ActiveModel::Validations

      attr_accessor :content

      validates :content, safe_html: true

      def self.name
        'SafeHtmlValidatorTestModel'
      end
    end
  end

  def valid_for(content)
    instance = model_class.new
    instance.content = content
    instance.valid?
    instance
  end

  describe 'rejects real HTML tag syntax' do
    it 'flags the pentest payload (samedis-care-backend issue #2417)' do
      instance = valid_for(%(NewTestFacility"><s>sss<h1>TEST</h1>))
      expect(instance.errors[:content]).to include('must not contain HTML tags')
    end

    it 'flags a script tag' do
      expect(valid_for('<script>alert(1)</script>').errors[:content]).to be_present
    end
  end

  describe 'accepts ordinary text' do
    it 'does not flag a bare ampersand (e.g. an organization name)' do
      expect(valid_for('Müller & Sohn GmbH').errors[:content]).to be_empty
    end
  end

  describe 'blank handling' do
    it 'does not flag nil' do
      expect(valid_for(nil).errors[:content]).to be_empty
    end

    it 'does not flag an empty string' do
      expect(valid_for('').errors[:content]).to be_empty
    end
  end

  describe '.strip_tags' do
    it 'strips a tag but keeps its inner text' do
      expect(described_class.strip_tags('<h1>Attacker</h1>')).to eq('Attacker')
    end

    it 'leaves ordinary text with an ampersand completely untouched' do
      # Loofah's own #text re-escapes "&" unconditionally -- only invoke it
      # when a tag is actually present, or plain text gets silently garbled.
      expect(described_class.strip_tags('Muller & Sohn')).to eq('Muller & Sohn')
    end

    it 'passes nil through unchanged' do
      expect(described_class.strip_tags(nil)).to be_nil
    end
  end
end
