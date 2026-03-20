module OpenapiSpec
  module Helpers

    def self.available_specs
      @available_specs ||= Dir.glob('spec/openapi/**/api_*.yaml').sort.collect do |file|
        dir = File.dirname(file)
        name = dir.split('/').last
        version = File.basename(file).match(/v\d+/)[0]
        spec = ActiveSupport::ConfigurationFile.parse(file)
        url = "/api-docs/#{version}/#{name}.yaml"
        destination = "public#{url}"
        title = spec.dig('info', 'title')

        {
          file:,
          dir:,
          version:,
          name:,
          url:,
          title:,
          spec:,
          destination:
        }
      end
    end

  end
end
