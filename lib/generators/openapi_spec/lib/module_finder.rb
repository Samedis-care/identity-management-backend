module OpenapiSpecGenerator::ModuleFinder
  extend self

  def find_controllers(for_api)
    Zeitwerk::Loader.eager_load_all
    Api::V1::JsonApiController.descendants.select do |klass|
      klass.const_defined?('API') && klass.const_get('API').eql?(for_api)
    end
  end

  def schemas(for_api = nil)
    for_api = for_api.to_sym
    controllers = find_controllers(for_api)
    serializers = controllers.flat_map do |controller|
      [
        (controller.const_get('SERIALIZER') rescue nil),
        (controller.const_get('OVERVIEW_SERIALIZER') rescue nil),
        (controller.const_get('SERIALIZERS') rescue nil)
      ]
    end.flatten.compact.uniq
    serializers.select! do |klass|
      has_schema_subclass?(klass)
    end
    _schemas = serializers.sort_by(&:name).collect do |serializer|
      _schema = serializer::Schema.new
      {
        _schema.openapi_component_name => _schema.openapi_component_produces_schema
      }.compact
    end

    _schemas.reduce({}, :merge).compact.sort.to_h
  end

  private

  def has_schema_subclass?(klass)
    klass = klass.call if klass.is_a?(Proc)
    klass.const_defined?('Schema') && klass.const_get('Schema').is_a?(Class)
  end
end
