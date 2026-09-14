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
    # ActiveStorage's filename column is 255 bytes on some databases; room is left for the detected extension.
    MAX_FILENAME_BYTES = 200
    BOOLEAN_TRUE = %w[true 1 t yes y on].freeze
    BOOLEAN_FALSE = %w[false 0 f no n off].freeze
    # Extension given to a base64 upload without a name (Rack::Mime's reverse lookup is first-match: .jpe).
    EXTENSIONS = {
      'application/pdf' => '.pdf', 'image/png' => '.png', 'image/jpeg' => '.jpg', 'image/gif' => '.gif',
      'image/webp' => '.webp', 'image/bmp' => '.bmp', 'image/tiff' => '.tiff',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => '.docx',
      'application/msword' => '.doc', 'application/vnd.oasis.opendocument.text' => '.odt',
      'application/rtf' => '.rtf', 'application/vnd.ms-excel' => '.xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => '.xlsx'
    }.freeze

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

    # Unreachable, slow, malformed or not a URL at all → Invalid with a translated reason, raised where the
    # download happens (the ingestion controllers rescue nothing wider than Invalid for it).
    def download(url)
      response = DownloadUtils.call(url, validate: true)
      filename = File.basename(CGI.unescapeURIComponent(URI.parse(url).path.to_s))

      [response.body, filename]
    rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
      raise Invalid, I18n.t('ccn_invalid_url')
    rescue Faraday::TimeoutError
      raise Invalid, I18n.t('ccn_download_timeout')
    rescue Faraday::Error
      raise Invalid, I18n.t('ccn_download_failed')
    end

    # `filename` is client-controlled: control characters and path separators go, only a plausible extension
    # reaches Tempfile (a 300-character "extension" would raise ENAMETOOLONG) and the name is cut to
    # MAX_FILENAME_BYTES.
    def build_uploaded_file(data, filename)
      filename = filename.to_s.gsub(%r{[[:cntrl:]/\\]}, '').squish.presence || 'document'
      extension = File.extname(filename)
      extension = '' unless extension.match?(/\A\.[A-Za-z0-9]{1,10}\z/)
      base = File.basename(filename, extension).truncate_bytes(MAX_FILENAME_BYTES, omission: '')
      filename = "#{base}#{extension}"

      tempfile = Tempfile.new(['ccn-document', extension])
      tempfile.binmode
      tempfile.write(data)
      tempfile.rewind

      type = Marcel::MimeType.for(tempfile, name: filename)
      filename += EXTENSIONS.fetch(type) { Rack::Mime::MIME_TYPES.key(type).to_s } if extension.blank?

      ActionDispatch::Http::UploadedFile.new(tempfile:, filename:, type:)
    end

    # @return [Array<Hash>] fields in the stored shape, with 'submitter_uuid' resolved (submitters created)
    def normalize_explicit_fields(fields, template, attachment_uuid)
      Array.wrap(fields).each_with_index.map do |field, index|
        field = indifferent(field)
        name, type = field_name_and_type!(field, index)
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

    def field_name_and_type!(field, index)
      name = field[:name].to_s.squish
      type = field[:type].presence || 'text'

      raise Invalid, "fields[#{index}][name] is required" if name.blank?
      raise Invalid, "fields[#{index}][type] '#{type}' is not supported" unless FIELD_TYPES.include?(type)

      [name, type]
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

    # `boolean` above is Rails' loose cast: every unrecognized non-empty string is true. That is the right
    # reading for a field flag, but it would let `dry_run=banana` silently pick the wrong mode on a
    # side-effecting endpoint, so a flag that changes what the request *does* parses strictly — anything
    # unrecognized is a client error (AdminErrors renders Invalid as a 422).
    def strict_boolean(value, name, default: false)
      return default if value.to_s.strip.blank?
      return value if [true, false].include?(value)

      normalized = value.to_s.strip.downcase

      return true if BOOLEAN_TRUE.include?(normalized)
      return false if BOOLEAN_FALSE.include?(normalized)

      raise Invalid, "#{name} must be true or false"
    end

    def indifferent(hash)
      hash = hash.to_unsafe_h if hash.respond_to?(:to_unsafe_h)

      hash.to_h.with_indifferent_access
    end
  end
end
