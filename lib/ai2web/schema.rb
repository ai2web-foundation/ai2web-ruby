# frozen_string_literal: true

module Ai2Web
  # Result of {Ai2Web.validate_schema}. `valid` is a boolean; `errors` is an array of strings.
  SchemaResult = Struct.new(:valid, :errors) do
    def valid? = valid
  end

  # Minimal JSON-Schema-subset validator for action input schemas. Port of @ai2web/core
  # validateSchema: pragmatic (object with typed/required properties, primitives, arrays, enum)
  # rather than the whole of JSON Schema. Used by the server to validate incoming requests
  # against an action's declared input_schema.
  module Schema
    module_function

    def type_of(value)
      case value
      when nil then "null"
      when true, false then "boolean"
      when Integer, Float then "number"
      when String then "string"
      when Array then "array"
      when Hash then "object"
      else "unknown"
      end
    end

    # Validate a value against a JSON-Schema-subset. An empty/absent schema accepts anything.
    def validate_schema(value, schema, path = "input")
      errors = []
      schema = Util.deep_stringify(schema)
      return SchemaResult.new(true, errors) unless schema.is_a?(Hash) && !schema.empty?

      value = Util.deep_stringify(value)
      declared = schema["type"]
      has_declared = declared.is_a?(String) && !declared.empty?

      if has_declared
        ok = if declared == "integer"
               value.is_a?(Integer) && value != true && value != false
             else
               type_of(value) == declared
             end
        unless ok
          errors << "#{path}: expected #{declared}, got #{type_of(value)}"
          return SchemaResult.new(false, errors) # wrong base type: stop
        end
      end

      enum = schema["enum"]
      errors << "#{path}: value is not one of the allowed options" if enum.is_a?(Array) && !enum.include?(value)

      is_object = value.is_a?(Hash)
      if (declared == "object" || (!has_declared && is_object)) && is_object
        props = schema["properties"].is_a?(Hash) ? schema["properties"] : {}
        (schema["required"] || []).each do |key|
          errors << "#{path}.#{key}: required" unless value.key?(key)
        end
        props.each do |key, sub|
          errors.concat(validate_schema(value[key], sub, "#{path}.#{key}").errors) if value.key?(key)
        end
      end

      if (declared == "array" || (!has_declared && value.is_a?(Array))) && value.is_a?(Array) && schema["items"]
        value.each_with_index do |item, i|
          errors.concat(validate_schema(item, schema["items"], "#{path}[#{i}]").errors)
        end
      end

      SchemaResult.new(errors.empty?, errors)
    end
  end

  module_function

  def validate_schema(value, schema, path = "input") = Schema.validate_schema(value, schema, path)
end
