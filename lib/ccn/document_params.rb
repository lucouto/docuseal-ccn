# frozen_string_literal: true

module Ccn
  # Turns the `documents[]` of the ingestion endpoints into the UploadedFile list Templates::CreateAttachments
  # expects (base64, data URI or https URL), and explicit `fields[]` into the stored field shape
  # (page 1-based → 0-based, role → submitter_uuid, option → option_uuid) — research D8.
  module DocumentParams
    class Invalid < StandardError; end

    URL_REGEXP = %r{\Ahttps?://}i
    DATA_URI_REGEXP = /\Adata:[^;,]*(?:;[^,]*)?,/i
    FIELD_TYPES = %w[text signature initials date number image checkbox multiple file radio select cells stamp
                     phone heading strikethrough].freeze

    module_function

    def files_from(documents)
      Array.wrap(documents).each_with_index.map do |document, index|
        document = indifferent(document)
        source = document[:file].to_s.strip

        raise Invalid, "documents[#{index}][file] is required" if source.blank?

        data, filename = source.match?(URL_REGEXP) ? download(source) : [decode(source, index), nil]
        filename = document[:name].presence || filename.presence || "document-#{index + 1}"

        build_uploaded_file(data, filename)
      end
    end

    def decode(source, index)
      Base64.strict_decode64(source.sub(DATA_URI_REGEXP, '').gsub(/\s/, ''))
    rescue ArgumentError
      raise Invalid, "documents[#{index}][file] is not valid base64 (or an https URL)"
    end

    def download(url)
      response = DownloadUtils.call(url, validate: true)
      filename = File.basename(URI.decode_www_form_component(URI.parse(url).path.to_s))

      [response.body, filename]
    end

    def build_uploaded_file(data, filename)
      tempfile = Tempfile.new(['ccn-document', File.extname(filename)])
      tempfile.binmode
      tempfile.write(data)
      tempfile.rewind

      type = Marcel::MimeType.for(tempfile, name: filename)
      filename += Rack::Mime::MIME_TYPES.key(type).to_s if File.extname(filename).blank?

      ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type:)
    end

    # @return [Array<Hash>] fields in the stored shape, with 'submitter_uuid' resolved (submitters created)
    def normalize_explicit_fields(fields, template, attachment_uuid)
      Array.wrap(fields).each_with_index.map do |field, index|
        field = indifferent(field)
        name = field[:name].to_s.squish
        type = field[:type].presence || 'text'

        raise Invalid, "fields[#{index}][name] is required" if name.blank?
        raise Invalid, "fields[#{index}][type] '#{type}' is not supported" unless FIELD_TYPES.include?(type)

        options = Array.wrap(field[:options]).map { |value| { 'uuid' => SecureRandom.uuid, 'value' => value.to_s } }
        areas = Array.wrap(field[:areas]).map do |area|
          normalize_area(indifferent(area), options, attachment_uuid, index)
        end

        {
          'uuid' => SecureRandom.uuid, 'name' => name, 'type' => type,
          'required' => field.key?(:required) ? boolean(field[:required]) : true,
          'readonly' => (true if boolean(field[:readonly])),
          'default_value' => field[:default_value].presence, 'title' => field[:title].presence,
          'description' => field[:description].presence,
          'options' => options.presence, 'preferences' => field[:preferences].to_h.presence,
          'validation' => field[:validation].to_h.presence,
          'submitter_uuid' => Ccn::AssignRoles.submitter_uuid_for(template, field[:role]),
          'areas' => areas
        }.compact
      end
    end

    def normalize_area(area, options, attachment_uuid, field_index)
      page = Integer(area[:page].to_s, 10, exception: false)

      if page.nil? || page < 1
        raise Invalid, "fields[#{field_index}].areas[].page must be a page number starting from 1"
      end

      attrs = {
        'page' => page - 1, 'x' => area[:x].to_f, 'y' => area[:y].to_f, 'w' => area[:w].to_f, 'h' => area[:h].to_f,
        'attachment_uuid' => attachment_uuid
      }

      if area[:option].present?
        option = options.find { |o| o['value'] == area[:option].to_s }
        option ||= { 'uuid' => SecureRandom.uuid, 'value' => area[:option].to_s }.tap { |o| options << o }

        attrs['option_uuid'] = option['uuid']
      end

      attrs
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def indifferent(hash)
      hash = hash.to_unsafe_h if hash.respond_to?(:to_unsafe_h)

      hash.to_h.with_indifferent_access
    end
  end
end
