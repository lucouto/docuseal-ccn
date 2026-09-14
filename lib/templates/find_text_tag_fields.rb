# frozen_string_literal: true

module Templates
  # CCN fork (FORK-PLAN.md §5.1): finds {{Name;attr=value;…}} text tags on every page and turns them into
  # fields in the same shape as FindPdfiumAcroFields, plus the rectangles to erase them with Page#redact.
  # Works on Pdfium::Page#text_nodes (one node per character, already sorted into lines), so tags split
  # into several text runs by Word are still found; a tag broken across two lines is left alone.
  module FindTextTagFields
    # No brace inside a tag: a stray '{{' earlier on the line cannot swallow the real tag that follows it.
    TAG_REGEXP = /\{\{([^{}]+?)\}\}/
    # Same threshold as Pdfium::Page#text_nodes' own line sort (4 pt, normalized by the page *width*), so the
    # groups below are exactly the lines pdfium ordered.
    LINE_THRESHOLD_PT = 4.0
    REDACTION_PADDING_PT = 1.0
    TYPES = %w[text signature initials date image file select checkbox radio number cells stamp phone
               multiple].freeze
    NAME_TYPES = %w[signature initials date].freeze
    # Pages beyond this are neither scanned nor erased (a page handle stays open per scanned page until the
    # document is closed); documents that long are not what text tags are for.
    MAX_PAGES = 200

    Tag = Struct.new(:name, :type, :role, :options, :required, :readonly, :default_value, :format,
                     :page, :box, :redact_rect)

    module_function

    # @return [Array(Array<Hash>, Hash{Integer => Array<Hash>})] fields (string keys, transient 'role') and
    #   redaction rectangles per 0-based page index
    def call(doc, attachment_uuid)
      tags = []

      # Pages are cached by the document (Document#get_page) and closed with it; closing them here would
      # hand a closed handle to the redaction step that follows.
      [doc.page_count, MAX_PAGES].min.times do |page_index|
        tags.concat(find_page_tags(doc.get_page(page_index), page_index))
      end

      return [[], {}] if tags.empty?

      [build_fields(tags, attachment_uuid), tags.group_by(&:page).transform_values { |ts| ts.map(&:redact_rect) }]
    end

    def find_page_tags(page, page_index)
      lines(page).flat_map do |nodes|
        text = nodes.map(&:content).join

        text.to_enum(:scan, TAG_REGEXP).filter_map do
          match = Regexp.last_match
          attrs = parse(match[1])

          next if attrs.nil?

          build_tag(attrs, nodes[match.begin(0)...match.end(0)], page, page_index)
        end
      end
    end

    # Groups the page's character nodes into lines: Pdfium::Page#text_nodes sorts them by the bottom of their
    # loose box (within LINE_THRESHOLD_PT / width) and then by x — the same partition is used here.
    def lines(page)
      threshold = LINE_THRESHOLD_PT / page.width

      page.text_nodes.slice_when { |a, b| (a.endy - b.endy).abs >= threshold }.to_a
    end

    # {{Name;attr=value;…}}: the first segment is the name unless it is itself an attribute (`name=…` names the
    # field, any other `key=value` first means the tag has no name). Returns nil for an unnamed tag.
    def parse(body)
      segments = body.split(';').map(&:strip)
      first = segments.shift.to_s
      attrs = {}

      if first.include?('=')
        segments.unshift(first)
      else
        attrs['name'] = first
      end

      segments.each do |segment|
        key, value = segment.split('=', 2)

        attrs[key.strip.downcase] = value.strip unless value.nil? || key.strip.empty?
      end

      attrs['name'].blank? ? nil : attrs
    end

    def build_tag(attrs, nodes, page, page_index)
      box, redact_rect = tag_boxes(attrs, nodes, page)

      Tag.new(
        name: attrs['name'],
        type: tag_type(attrs),
        role: attrs['role'].presence,
        options: attrs['options'].to_s.split(',').map(&:strip).compact_blank,
        required: attrs['required'].nil? || attrs['required'].casecmp?('true'),
        readonly: attrs['readonly'].to_s.casecmp?('true'),
        default_value: attrs['default'].presence,
        format: attrs['format'].presence,
        page: page_index, box:, redact_rect:
      )
    end

    # Field box = the union of the tag's characters (page-normalized), unless width/height in points override
    # it, anchored at the tag's top-left. The redaction rectangle is always the character union, padded.
    # @return [Array(Hash, Hash)] [box, redact_rect]
    def tag_boxes(attrs, nodes, page)
      x = nodes.map(&:x).min
      y = nodes.map(&:y).min
      w = nodes.map(&:endx).max - x
      h = nodes.map(&:endy).max - y

      width = attrs['width'].to_f
      height = attrs['height'].to_f
      pad_x = REDACTION_PADDING_PT / page.width
      pad_y = REDACTION_PADDING_PT / page.height

      box = { 'x' => x, 'y' => y,
              'w' => width.positive? ? width / page.width : w,
              'h' => height.positive? ? height / page.height : h }
      # 'white' tells Page#redact to erase the characters without painting a rectangle (any other value
      # paints a black bar — lib/pdfium.rb draw_redaction_rects).
      redact_rect = { 'x' => x - pad_x, 'y' => y - pad_y, 'w' => w + (2 * pad_x), 'h' => h + (2 * pad_y),
                      'color' => 'white' }

      [box, redact_rect]
    end

    def tag_type(attrs)
      type = attrs['type'].to_s.strip.downcase

      return type if TYPES.include?(type)
      return attrs['name'].downcase if type.empty? && NAME_TYPES.include?(attrs['name'].downcase)

      'text'
    end

    def build_options(values)
      return if values.empty?

      values.map { |value| { 'uuid' => SecureRandom.uuid, 'value' => value } }
    end

    def build_fields(tags, attachment_uuid)
      tags.group_by { |tag| [tag.name, tag.role] }.map do |(name, role), group|
        first = group.first

        {
          'uuid' => SecureRandom.uuid,
          'name' => name,
          'type' => first.type,
          'required' => first.required,
          'readonly' => (true if first.readonly),
          'default_value' => first.default_value,
          'options' => build_options(first.options),
          'preferences' => first.format ? { 'format' => first.format } : {},
          'role' => role,
          'areas' => group.map { |tag| tag.box.merge('page' => tag.page, 'attachment_uuid' => attachment_uuid) }
        }.compact
      end
    end
  end
end
