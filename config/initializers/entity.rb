module JSON
  module SchemaBuilder
    class Entity
      # adding some missing attributes to allow for OAS 3
      attribute :write_only, as: :writeOnly
      attribute :read_only, as: :readOnly
      attribute :deprecated
      attribute :nullable # for OAS3.0
      attribute :example  # for OAS3.0
      attribute :examples # for OAS3.1
    end
  end
end
