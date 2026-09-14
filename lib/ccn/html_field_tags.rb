# frozen_string_literal: true

module Ccn
  # Turns DocuSeal's HTML field elements (<text-field name="…" role="…" style="width:200px;height:24px">)
  # into self-describing text tags, so one detector (Templates::FindTextTagFields) serves PDF, DOCX and HTML
  # (FORK-PLAN.md §5.3, research D6). Each element becomes an inline block of the element's size carrying,
  # at its top-left, a 1 px white {{name;type=…;role=…;width=W;height=H}} marker; Chromium renders the page,
  # the detector anchors a W × H field at the marker and erases it (white on white anyway).
  module HtmlFieldTags
    FIELD_TYPES = %w[text signature initials date image file select checkbox radio number phone stamp cells
                     multiple].freeze
    PASSTHROUGH_ATTRIBUTES = %w[role required readonly default options format].freeze
    PX_TO_PT = 0.75
    DEFAULT_SIZES_PX = {
      'signature' => [200, 60], 'initials' => [100, 40], 'stamp' => [120, 60], 'image' => [200, 120],
      'checkbox' => [16, 16], 'radio' => [16, 16]
    }.freeze
    DEFAULT_SIZE_PX = [160, 24].freeze
    MARKER_STYLE = 'position:absolute;left:0;top:0;margin:0;padding:0;font-size:1px;line-height:1px;' \
                   'font-family:Helvetica,Arial,sans-serif;color:#ffffff;white-space:nowrap'

    module_function

    # @return [String] the rewritten HTML document
    def call(html)
      doc = Nokogiri::HTML5(html.to_s)
      counter = Hash.new(0)

      FIELD_TYPES.each do |type|
        doc.css("#{type}-field").each do |node|
          counter[type] += 1

          node.replace(build_field_node(doc, node, type, counter[type]))
        end
      end

      doc.to_html
    end

    def build_field_node(doc, node, type, index)
      width_px, height_px = element_size_px(node, type)
      name = sanitize(node['name'].presence || "#{type.capitalize} #{index}")

      attributes = ["type=#{type}"]
      PASSTHROUGH_ATTRIBUTES.each do |attribute|
        value = node[attribute]

        attributes << "#{attribute}=#{sanitize(value)}" if value.present?
      end
      attributes << "width=#{(width_px * PX_TO_PT).round(2)}" << "height=#{(height_px * PX_TO_PT).round(2)}"

      wrapper = doc.create_element('span')
      wrapper['style'] = "display:inline-block;position:relative;vertical-align:top;" \
                         "width:#{width_px}px;height:#{height_px}px;#{node['style']}"
      wrapper['data-ccn-field'] = type

      marker = doc.create_element('span')
      marker['style'] = MARKER_STYLE
      marker.content = "{{#{name};#{attributes.join(';')}}}"

      wrapper.add_child(marker)
      wrapper
    end

    def element_size_px(node, type)
      style = node['style'].to_s
      width = style[/(?:^|;)\s*width\s*:\s*([\d.]+)px/i, 1] || node['width']
      height = style[/(?:^|;)\s*height\s*:\s*([\d.]+)px/i, 1] || node['height']
      default_width, default_height = DEFAULT_SIZES_PX.fetch(type, DEFAULT_SIZE_PX)

      [positive_or(width, default_width), positive_or(height, default_height)]
    end

    def positive_or(value, default)
      number = value.to_s[/[\d.]+/].to_f

      number.positive? ? number : default
    end

    # Tag syntax uses ';' and '}}' as delimiters and '=' inside attributes.
    def sanitize(value)
      value.to_s.gsub(/[;{}]/, ' ').squish
    end
  end
end
