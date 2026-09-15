# frozen_string_literal: true

module Ccn
  # Stage 4, US4 (specs/003-p1-features, research D11): a spreadsheet of signers turned into one submission
  # per row. The API has done bulk sending since Stage 2; this is the same thing for the staff who do not use
  # it, so it deliberately produces the attributes `Submissions.create_from_submitters` already takes — the
  # very path POST /api/submissions uses — rather than a second way of creating a submission.
  #
  # The whole file is refused when any row is wrong (FR-010). Sending half a list and reporting the rest is
  # the worst outcome for the person holding the spreadsheet: they cannot tell what went out.
  module SubmissionsLists
    Invalid = Class.new(StandardError)

    MAX_ROWS = 500
    MAX_BYTES = 5.megabytes
    PREVIEW_ROWS = 5
    MAX_REPORTED_ERRORS = 20
    ATTRIBUTES = %w[email name phone].freeze
    XLSX_TYPES = ['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  'application/vnd.ms-excel'].freeze

    module_function

    # @return [Hash] 'columns', 'rows_count', 'preview' (the first rows as shown), 'errors'
    #   ([{ 'line', 'error' }], empty when the file is usable) and 'submissions_attrs' (empty unless it is).
    def parse(file, template)
      header, body = read(file)
      columns = resolve_columns(header, template)

      raise Invalid, I18n.t('ccn_list_email_column_required') if columns.none? { |c| c[:attribute] == 'email' }

      rows = body.each_with_index.map { |cells, index| build_row(cells, columns, index + 2) }
      errors = rows.flat_map { |row| row[:errors] }.first(MAX_REPORTED_ERRORS)

      { 'columns' => header, 'rows_count' => rows.size, 'errors' => errors,
        'preview' => rows.first(PREVIEW_ROWS).pluck(:preview),
        'submissions_attrs' => errors.empty? ? rows.pluck(:attrs) : [] }
    end

    # @return [Array(Array<String>, Array<Array>)] the header row and the rows under it, blank rows dropped.
    def read(file)
      raise Invalid, I18n.t('ccn_list_file_required') if file.blank?
      raise Invalid, I18n.t('ccn_list_too_large', max: MAX_BYTES / 1.megabyte) if file.size.to_i > MAX_BYTES

      table = xlsx?(file) ? read_xlsx(file) : read_csv(file)
      table = table.reject { |row| row.all? { |cell| cell.to_s.strip.blank? } }

      raise Invalid, I18n.t('ccn_list_empty') if table.blank?

      header = table.first.map { |cell| cell.to_s.strip }
      body = table.drop(1)

      raise Invalid, I18n.t('ccn_list_too_many_rows', max: MAX_ROWS) if body.size > MAX_ROWS

      [header, body]
    end

    def xlsx?(file)
      return true if file.content_type.to_s.in?(XLSX_TYPES)

      File.extname(file.original_filename.to_s).casecmp?('.xlsx')
    end

    def read_csv(file)
      CSV.parse(file.read.to_s.force_encoding('UTF-8').scrub, headers: false)
    rescue CSV::MalformedCSVError => e
      raise Invalid, I18n.t('ccn_list_unreadable', message: e.message.to_s.truncate(120))
    end

    # First sheet only (research D11). rubyXL reads the value a formula last evaluated to, which is what the
    # person saw in the spreadsheet, and what they mean.
    def read_xlsx(file)
      sheet = RubyXL::Parser.parse_buffer(file.read)&.worksheets&.first

      raise Invalid, I18n.t('ccn_list_empty') if sheet.nil?

      sheet.map { |row| Array(row&.cells).map { |cell| cell&.value } }
    rescue Invalid
      raise
    rescue StandardError => e
      raise Invalid, I18n.t('ccn_list_unreadable', message: e.message.to_s.truncate(120))
    end

    # A column is `email`, `name`, `phone` or the name of a prefillable field — prefixed by the role when the
    # template has more than one, as `Signer: email`. A column naming none of those is dropped rather than
    # refused, so an export with extra columns can be uploaded as it comes; because the preview shows only the
    # columns that were understood, a misspelt header is visible as a missing column rather than silent.
    # @return [Array<Hash>] { index:, submitter_uuid:, attribute: } or { index:, submitter_uuid:, field: }
    def resolve_columns(header, template)
      submitters = template.submitters.to_a
      fields = template.fields.to_a.select { |field| field['prefillable'] }

      header.each_with_index.filter_map do |name, index|
        role, key = split_role(name, submitters)
        submitter = submitters.find { |s| s['name'].to_s.casecmp?(role.to_s) } || (submitters.first if role.nil?)

        next if submitter.nil? || key.blank?

        # `name` is the header as written: two roles each have an `email` column, and the preview has to show
        # them apart.
        column = { index:, name:, submitter_uuid: submitter['uuid'] }
        field = fields.find { |f| f['name'].to_s.casecmp?(key) && f['submitter_uuid'] == submitter['uuid'] }

        if ATTRIBUTES.include?(key.downcase) then column.merge(attribute: key.downcase)
        elsif field then column.merge(field:)
        end
      end
    end

    def split_role(name, submitters)
      role, _, rest = name.to_s.partition(':')

      return [nil, name.to_s.strip] if rest.blank? || submitters.none? { |s| s['name'].to_s.casecmp?(role.strip) }

      [role.strip, rest.strip]
    end

    def build_row(cells, columns, line)
      preview = {}
      by_submitter = Hash.new { |hash, uuid| hash[uuid] = { uuid:, values: {} } }

      columns.each do |column|
        value = cells[column[:index]].to_s.strip
        preview[column[:name]] = value

        next if value.blank?

        submitter = by_submitter[column[:submitter_uuid]]

        if column[:attribute] then submitter[column[:attribute].to_sym] = value
        else submitter[:values][column[:field]['uuid']] = value
        end
      end

      submitters = by_submitter.values.select { |s| s[:email].present? }

      { preview:, attrs: { submitters: }, errors: row_errors(submitters, line) }
    end

    def row_errors(submitters, line)
      return [{ 'line' => line, 'error' => I18n.t('ccn_list_row_email_required') }] if submitters.blank?

      submitters.filter_map do |submitter|
        next if valid_email?(submitter[:email])

        { 'line' => line, 'error' => I18n.t('ccn_list_row_invalid_email', email: submitter[:email].truncate(60)) }
      end
    end

    # The rule Params::BaseValidator applies to a submitter's e-mail on the API, typo correction included, so
    # that a row this accepts is a row POST /api/submissions would have accepted too.
    def valid_email?(email)
      return false if email.include?('<')

      EmailTypo::DotCom.call(email).match?(User::FULL_EMAIL_REGEXP) || email.include?('--')
    end
  end
end
