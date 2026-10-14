require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#2815.
#
# public/api-docs/v1/ident.yaml was a published OpenAPI bundle with no source under
# spec/openapi, so `rake openapi_spec:combine` could never regenerate it: it froze in
# March while the controllers it documented kept changing, and it was served from the
# static public/ directory with no signal that it was abandoned.
RSpec.describe 'published OpenAPI bundles' do
  let(:published) { Dir.glob(Rails.root.join('public/api-docs/v*/*.yaml').to_s) }
  let(:sources) do
    Dir.glob(Rails.root.join('spec/openapi/*/api_v*.yaml').to_s).map do |file|
      File.join(File.basename(File.dirname(file)), file[/v\d+/])
    end
  end

  it 'has a source under spec/openapi for every bundle served from public/api-docs' do
    served = published.map { |file| File.join(File.basename(file, '.yaml'), file[%r{api-docs/(v\d+)/}, 1]) }

    expect(served - sources).to be_empty
  end

  it 'finds a published bundle for every source (combine writes it)' do
    served = published.map { |file| File.join(File.basename(file, '.yaml'), file[%r{api-docs/(v\d+)/}, 1]) }

    expect(sources - served).to be_empty
  end

  it 'only points controller header comments at spec files that exist' do
    dangling = Dir.glob(Rails.root.join('app/controllers/**/*.rb').to_s).filter_map do |file|
      target = File.foreach(file).first.to_s[/\A# OpenAPI spec: (\S+)/, 1]
      "#{file.delete_prefix("#{Rails.root}/")} -> #{target}" if target && !Rails.root.join(target).exist?
    end

    expect(dangling).to be_empty
  end
end
