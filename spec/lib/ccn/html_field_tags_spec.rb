# frozen_string_literal: true

describe Ccn::HtmlFieldTags do
  let(:html) do
    <<~HTML
      <h1>Lease</h1>
      <p>Tenant:
        <text-field name="Tenant" role="Tenant" required="false" style="width:200px;height:24px"></text-field>
      </p>
      <signature-field name="Sign here" role="Tenant"></signature-field>
      <select-field name="Plan" options="Basic,Plus" style="height:30px"></select-field>
      <date-field></date-field>
    HTML
  end
  let(:result) { described_class.call(html) }

  it 'replaces every field element with a sized span carrying a hidden text tag' do
    expect(result).not_to include('<text-field', '<signature-field', '<select-field', '<date-field')
    expect(result).to include('{{Tenant;type=text;role=Tenant;required=false;width=150.0;height=18.0}}')
    expect(result).to include('width:200px;height:24px')
  end

  it 'falls back to per-type default sizes when the element has no CSS size' do
    expect(result).to include('{{Sign here;type=signature;role=Tenant;width=150.0;height=45.0}}')
    expect(result).to include('{{Plan;type=select;options=Basic,Plus;width=120.0;height=22.5}}')
  end

  it 'names unnamed fields after their type and index' do
    expect(result).to include('{{Date 1;type=date;width=120.0;height=18.0}}')
  end

  it 'keeps the marker invisible and unwrapped' do
    expect(result).to include('font-size:1px').and include('color:#ffffff').and include('white-space:nowrap')
  end

  it 'strips tag delimiters from user-supplied names and values' do
    html = '<text-field name="a;b}}c" default="x;y"></text-field>'

    expect(described_class.call(html)).to include('{{a b c;type=text;default=x y;width=120.0;height=18.0}}')
  end

  it 'leaves unrelated markup untouched' do
    expect(result).to include('<h1>Lease</h1>')
  end
end
