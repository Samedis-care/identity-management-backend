module ActiveModel
  # == Active \Model \Error
  #
  # Represents one single error
  class Error

    def self.full_message(attribute, message, base) # :nodoc:
      return message if attribute == :base

      base_class = base.class
      attribute = attribute.to_s

      if i18n_customize_full_message && base_class.respond_to?(:i18n_scope)

        attribute = attribute.remove(/\[\d+\]/)
        parts = attribute.split(".")
        attribute_name = parts.pop
        namespace = parts.join("/") unless parts.empty?
        attributes_scope = "#{base_class.i18n_scope}.errors.models"

        if namespace
          defaults = base_class.lookup_ancestors.map do |klass|
            [
              :"#{attributes_scope}.#{klass.model_name.i18n_key}/#{namespace}.attributes.#{attribute_name}.format",
              :"#{attributes_scope}.#{klass.model_name.i18n_key}/#{namespace}.format",
            ]
          end
        else
          defaults = base_class.lookup_ancestors.map do |klass|
            [
              :"#{attributes_scope}.#{klass.model_name.i18n_key}.attributes.#{attribute_name}.format",
              :"#{attributes_scope}.#{klass.model_name.i18n_key}.format",
            ]
          end
        end

        defaults.flatten!
      else
        defaults = []
      end

      attr_name = attribute.tr(".", "_").humanize
      attr_name = base_class.human_attribute_name(attribute, {
        default: attr_name,
        base: base,
      })

      # MOD: don't add attribute name as prefix
      # if the translated attribute is already included 
      # in the localized message.
      if message =~ Regexp.new(/\b#{attr_name}\b/i)
        defaults << "%{message}"
      end
      defaults << :"errors.format"
      defaults << "%{attribute} %{message}"

      I18n.t(defaults.shift,
        default:  defaults,
        attribute: attr_name,
        message:   message)
    end
  end

end
