require 'rails_helper'
require Rails.root.join('lib/generators/openapi_spec/lib/helpers').to_s

# Regression coverage for Samedis-care/samedis-care-issues#2815.
#
# public/api-docs/v1/ident.yaml was a published OpenAPI bundle with no source under
# spec/openapi, so `rake openapi_spec:combine` could never regenerate it: it froze in
# March while the controllers it documented kept changing, and it was served from the
# static public/ directory with no signal that it was abandoned.
RSpec.describe 'published OpenAPI bundles' do
  # compare against exactly what `combine` writes, not a re-derived source glob
  let(:generated) { OpenapiSpec::Helpers.available_specs.map { |spec| spec[:destination] } }
  let(:published) { Dir.glob('public/api-docs/v*/*.yaml') }

  it 'has a source under spec/openapi for every bundle served from public/api-docs' do
    expect(published - generated).to be_empty
  end

  it 'finds a published bundle for every source (combine writes it)' do
    expect(generated - published).to be_empty
  end

  it 'only points controller header comments at spec files that exist' do
    dangling = Dir.glob(Rails.root.join('app/controllers/**/*.rb').to_s).filter_map do |file|
      target = File.foreach(file).first.to_s[/\A# OpenAPI spec: (\S+)/, 1]
      "#{file.delete_prefix("#{Rails.root}/")} -> #{target}" if target && !Rails.root.join(target).exist?
    end

    expect(dangling).to be_empty
  end
end
