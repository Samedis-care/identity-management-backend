require 'rails_helper'

# app.config.mailer.logo_b64 is client-settable (Api::V1::AppAdminController
# permits it) and #logo hands it to libvips with no uploader in front, so it needs
# its own MIME gate: config/initializers/vips.rb re-enables the SVG loader
# process-wide, which would otherwise let an app admin have librsvg parse an SVG
# during mail rendering.
describe DeviseMailer, type: :mailer do
  let(:mailer) { described_class.new }

  def stub_logo(bytes, declared_mime)
    b64 = "data:#{declared_mime};base64,#{Base64.strict_encode64(bytes)}"
    app = OpenStruct.new(config: OpenStruct.new(mailer: OpenStruct.new(logo_b64: b64)))
    allow(mailer).to receive(:app).and_return(app)
  end

  it 'loads a PNG logo' do
    stub_logo(Vips::Image.black(8, 8).write_to_buffer('.png'), 'image/png')
    expect(mailer.send(:logo)).to be_a(Vips::Image)
  end

  it 'ignores an SVG logo even though the SVG loader is unblocked' do
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8"/></svg>'
    stub_logo(svg, 'image/svg+xml')
    expect(mailer.send(:logo)).to be_nil
  end

  it 'ignores a logo whose declared image/png contradicts its content' do
    stub_logo("%PDF-1.4\n1 0 obj\n<< >>\nendobj\ntrailer\n<< >>\n%%EOF\n", 'image/png')
    expect(mailer.send(:logo)).to be_nil
  end

  it 'attaches nothing when the logo is rejected' do
    stub_logo("P3\n1 1\n255\n0 0 0\n", 'image/png')
    mailer.send(:logo)
    expect(mailer.attachments['logo.png']).to be_nil
  end

  it 'accepts a GIF, which rendered fine before this gate existed' do
    stub_logo(Vips::Image.black(8, 8).write_to_buffer('.gif'), 'image/gif')
    expect(mailer.send(:logo)).to be_a(Vips::Image)
  rescue Vips::Error
    skip 'this libvips build cannot write GIF'
  end

  # prepare_logo -> logo_size -> logo_width/height/style each call #logo, so a
  # rejection that does not memoise costs five base64 decodes, five Tempfiles,
  # five marcel sniffs and five identical warnings for every mail that app sends.
  it 'builds the logo once even when it is rejected' do
    stub_logo("P3\n1 1\n255\n0 0 0\n", 'image/png')
    allow(mailer).to receive(:build_logo).and_call_original
    mailer.send(:prepare_logo)
    expect(mailer).to have_received(:build_logo).once
  end

  it 'builds the logo once when it is accepted' do
    stub_logo(Vips::Image.black(8, 8).write_to_buffer('.png'), 'image/png')
    allow(mailer).to receive(:build_logo).and_call_original
    mailer.send(:prepare_logo)
    expect(mailer).to have_received(:build_logo).once
  end
end
