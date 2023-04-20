# frozen_string_literal: true
# encoding: utf-8

# taken from mongoid 7.3.4
module Mongoid
  module Validatable

    class PresenceValidator < ActiveModel::EachValidator

      # add control to which languages are required
      # via #validate_presence_for_languages
      # which for example can return all or just the default language
      def validate_each(document, attribute, value)
        field = document.fields[document.database_field_name(attribute)]
        if field.try(:localized?) && !value.blank?
          _langs = document.try(:validate_presence_for_languages)&.compact || value&.keys || []
          value.slice(*_langs).each_pair do |_locale, _value|
            document.errors.add(
              attribute,
              :blank_in_locale,
              **options.merge(location: _locale)
            ) if not_present?(_value)
          end
        elsif document.relations.has_key?(attribute.to_s)
          if relation_or_fk_missing?(document, attribute, value)
            document.errors.add(attribute, :blank, **options)
          end
        else
          document.errors.add(attribute, :blank, **options) if not_present?(value)
        end
      end

    end
  end
end
