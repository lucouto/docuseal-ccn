# frozen_string_literal: true

# CCN fork — helpers for the API contract test (spec/requests/openapi_contract_spec.rb).
#
# Upstream ships its public API description in docs/openapi.json (paths are relative to
# https://api.docuseal.com, i.e. mounted under /api here). This module answers two questions
# without any extra gem: is an operation routable in this build, and does a real response
# match the operation's declared response schema (type, required, properties, items,
# oneOf/anyOf/allOf, OpenAPI 3.1 type arrays such as ["string", "null"]).
module OpenapiContract
  SPEC_PATH = Rails.root.join('docs/openapi.json')
  HTTP_METHODS = %w[get post put patch delete].freeze
  SAMPLE_ID = '1'

  module_function

  def spec(path = SPEC_PATH)
    (@specs ||= {})[path.to_s] ||= JSON.parse(path.read)
  end

  # => [{ method: 'get', path: '/templates', operation: {...} }, ...]
  def operations(path = SPEC_PATH)
    spec(path)['paths'].flat_map do |route, methods|
      methods.slice(*HTTP_METHODS).map do |method, operation|
        { method:, path: route, operation: }
      end
    end
  end

  def api_path(path, id: SAMPLE_ID)
    "/api#{path.gsub(/\{[^}]+\}/, id.to_s)}"
  end

  def routable?(method, path)
    Rails.application.routes.recognize_path(api_path(path), method: method.upcase)

    true
  rescue ActionController::RoutingError
    false
  end

  def response_schema(operation, status = '200')
    operation.dig('responses', status.to_s, 'content', 'application/json', 'schema')
  end

  # Returns an array of human-readable mismatch descriptions (empty when the value conforms).
  def validate(value, schema, at = '$')
    return [] if schema.blank?
    return validate_composite(value, schema, at) if composite?(schema)

    errors = validate_type(value, schema, at)
    return errors if errors.any? || value.nil?

    case value
    when Hash then errors + validate_object(value, schema, at)
    when Array then errors + validate_array(value, schema, at)
    else errors
    end
  end

  def composite?(schema)
    schema.key?('oneOf') || schema.key?('anyOf') || schema.key?('allOf')
  end

  def validate_composite(value, schema, at)
    return schema['allOf'].flat_map { |sub| validate(value, sub, at) } if schema['allOf']

    alternatives = schema['oneOf'] || schema['anyOf']
    results = alternatives.map { |sub| validate(value, sub, at) }

    return [] if results.any?(&:empty?)

    ["#{at}: matches none of #{alternatives.size} alternatives (#{results.flatten.first(3).join(' | ')})"]
  end

  def validate_type(value, schema, at)
    types = Array.wrap(schema['type'])

    return [] if types.empty?
    return [] if types.any? { |type| type_matches?(value, type) }

    ["#{at}: expected #{types.join('|')}, got #{value.nil? ? 'null' : value.class.name} #{value.inspect.truncate(60)}"]
  end

  def type_matches?(value, type)
    case type
    when 'null' then value.nil?
    when 'object' then value.is_a?(Hash)
    when 'array' then value.is_a?(Array)
    when 'string' then value.is_a?(String)
    when 'integer' then value.is_a?(Integer)
    when 'number' then value.is_a?(Numeric)
    when 'boolean' then value == true || value == false
    else true
    end
  end

  def validate_object(value, schema, at)
    missing = Array.wrap(schema['required']).reject { |key| value.key?(key) }
    errors = missing.map { |key| "#{at}: missing required key #{key.inspect}" }

    (schema['properties'] || {}).each do |key, sub|
      next unless value.key?(key)

      errors += validate(value[key], sub, "#{at}.#{key}")
    end

    errors
  end

  def validate_array(value, schema, at)
    return [] if schema['items'].blank?

    value.first(20).each_with_index.flat_map { |item, index| validate(item, schema['items'], "#{at}[#{index}]") }
  end
end
