require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3215, at the level of what is PUBLISHED.
# The generator override alone is not enough: the committed bundles are only changed by hand-patching
# the affected blocks (a full combine drags in unrelated drift, #2684), and a review found four
# endpoints whose committed docs still said `image` is an object {large, medium, small} although the
# controllers permit a scalar.
RSpec.describe 'published OpenAPI request bodies' do
  bundles = Dir.glob('public/api-docs/v*/*.yaml')

  def request_bodies(spec)
    spec.fetch('paths', {}).flat_map do |path, operations|
      operations.filter_map do |method, operation|
        next unless operation.is_a?(Hash) && operation['requestBody']

        ["#{method.upcase} #{path}", operation.dig('requestBody', 'content') || {}]
      end
    end
  end

  it 'finds the bundles it is meant to check' do
    expect(bundles).not_to be_empty
  end

  bundles.each do |bundle|
    describe bundle do
      let(:spec) { YAML.load_file(Rails.root.join(bundle), aliases: true) }

      it 'never publishes image as a response-style object in a request body' do
        offenders = request_bodies(spec).flat_map do |operation, content|
          json_image = content.dig('application/json', 'schema', 'properties', 'data', 'properties', 'image')
          fields = content.except('application/json').flat_map { |_type, body| body.dig('schema', 'properties')&.keys || [] }

          [
            ("#{operation}: JSON image is an object" if json_image && json_image['type'].to_s.eql?('object')),
            *fields.grep(/\Adata\[image\]\[/).map { |field| "#{operation}: form field #{field}" }
          ].compact
        end

        expect(offenders).to be_empty
      end

      it 'documents the blacklist `active` as a boolean wherever its description appears' do
        text = File.read(Rails.root.join(bundle))
        stale = text.scan(/(?:active|data\[active\]):\n( *)type: string\n\1description: controls if the domain name is actively being blacklisted/)

        expect(stale).to be_empty
      end
    end
  end
end
