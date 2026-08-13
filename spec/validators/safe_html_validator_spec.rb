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

  # PR #276 review (@SCjona) found the parser-only check has real bypasses:
  # verified all three empirically before fixing, not just accepted them.
  describe 'catches what the HTML5-fragment-parser-only check missed' do
    it 'flags a no-tag attribute breakout (zero "<", so no Element node is possible)' do
      instance = valid_for(%(NewTestFacility" autofocus onfocus=alert(1) x="))
      expect(instance.errors[:content]).to be_present
    end

    it 'flags <body onload=...> (fragment parsing ignores body/html start tags -- no Element child results)' do
      expect(valid_for('<body onload=alert(1)>').errors[:content]).to be_present
    end

    it 'flags a table-scoped tag outside a table (fragment parsing drops it -- no Element child results)' do
      expect(valid_for('<td onmouseover=alert(1)>x</td>').errors[:content]).to be_present
    end

    it 'flags an EOF-truncated tag (no closing ">" -- tokenizer discards the pending tag token as a parse error)' do
      expect(valid_for('NewTestFacility<img src=x onerror=alert(1)').errors[:content]).to be_present
    end
  end

  describe 'accepts ordinary text' do
    it 'does not flag a bare ampersand (e.g. an organization name)' do
      expect(valid_for('Müller & Sohn GmbH').errors[:content]).to be_empty
    end

    it 'does not flag an apostrophe (legitimate names commonly contain one, e.g. O\'Brien, L\'Oréal)' do
      expect(valid_for("O'Brien's Medical Group").errors[:content]).to be_empty
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

    it 'removes the unsafe characters directly when there is no real tag to unwrap' do
      result = described_class.strip_tags(%(NewTestFacility" autofocus onfocus=alert(1) x="))
      expect(result).not_to match(/[<>"]/)
    end

    it 'does not leave entity-escaping garbage behind for the no-real-tag case' do
      result = described_class.strip_tags(%(NewTestFacility" autofocus onfocus=alert(1) x="))
      expect(result).not_to include('&quot;')
    end

    it 'leaves an apostrophe untouched even when other content needed cleaning' do
      result = described_class.strip_tags(%(O'Brien" autofocus x="))
      expect(result).to include("O'Brien")
    end
  end
end
