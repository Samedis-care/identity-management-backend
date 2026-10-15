require 'rails_helper'

# Regression coverage for Samedis-care/samedis-care-issues#3215: the generated request bodies were
# derived from the RESPONSE schema, so `image` was published as an object {large, medium, small}
# (the controller permits a scalar: a client following the spec had it silently dropped) and
# EmailBlacklistSerializer declared the boolean `active` as a string.
RSpec.describe 'OpenAPI request body schemas' do
  def data_properties(schema)
    schema.dig(:properties, :data, :properties)
  end

  describe 'image' do
    let(:serializer_schema) { ActorSerializer::Schema.new }

    it 'is a single file upload in the JSON request body, not the response object' do
      image = data_properties(serializer_schema.openapi_consumes_schema(only: %i[image image_b64]))[:image]

      expect(image).to include(type: 'string', format: 'binary')
      expect(image).not_to have_key(:properties)
    end

    it 'is a single form field in the form-data request body, not data[image][large] and friends' do
      form = serializer_schema.openapi_consumes_form_data_schema(only: %i[image image_b64])
      fields = form[:properties].keys.map(&:to_s)

      expect(fields).to include('data[image]', 'data[image_b64]')
      expect(fields.grep(/data\[image\]\[/)).to be_empty
    end

    it 'keeps the style-URL object in the RESPONSE schema, which is what a response carries' do
      image = serializer_schema.openapi_component_produces_schema.dig(:properties, :image)

      expect(image[:type].to_s).to eq('object')
      expect(image[:properties].keys.map(&:to_s)).to include('large', 'medium', 'small')
    end

    it 'does not touch the schema memoized for the response (the override works on a copy)' do
      serializer_schema.openapi_consumes_schema(only: %i[image])

      expect(serializer_schema.openapi_component_produces_schema.dig(:properties, :image)[:type].to_s).to eq('object')
    end

    # every serializer that describes image as an object (user, app admin, ...) gets the same fix
    it 'is overridden for every serializer that publishes image as an object' do
      Rails.application.eager_load!
      serializers = ObjectSpace.each_object(Class).select { |klass| klass.name&.end_with?('Serializer::Schema') }
      expect(serializers.size).to be > 5

      offenders = serializers.filter_map do |klass|
        produced = klass.new.openapi_component_produces_schema.dig(:properties, :image)
        next unless produced && produced[:type].to_s.eql?('object')

        image = data_properties(klass.new.openapi_consumes_schema(only: %i[image]))&.dig(:image)
        klass.name unless image.nil? || image[:type].to_s.eql?('string')
      end

      expect(offenders).to be_empty
    end
  end

  # the override's description points JSON clients at image_b64, so every endpoint that publishes the
  # image override must also list image_b64 in its request body (review of the first version: the
  # tenants endpoint did not, because TenantSerializer's schema had no image_b64)
  describe 'image_b64' do
    it 'is listed, write-only, in the request body of the tenants serializer next to image' do
      properties = data_properties(TenantSerializer::Schema.new.openapi_consumes_schema(only: %i[image image_b64]))

      expect(properties.keys).to include(:image, :image_b64)
      expect(properties[:image_b64]).to include(type: 'string', writeOnly: true)
    end
  end

  describe 'EmailBlacklistSerializer active' do
    let(:serializer_schema) { EmailBlacklistSerializer::Schema.new }

    it 'is a boolean in the response schema' do
      expect(serializer_schema.openapi_component_produces_schema.dig(:properties, :active)[:type].to_s).to eq('boolean')
    end

    it 'is a boolean in the request body' do
      active = data_properties(serializer_schema.openapi_consumes_schema(only: %i[domain active]))[:active]

      expect(active[:type].to_s).to eq('boolean')
    end
  end
end
