require "rails_helper"
require "fileutils"
require "generators/instagram_connect/views_generator"

RSpec.describe InstagramConnect::Generators::ViewsGenerator do
  let(:dest) { File.expand_path("../../tmp/views_dest", __dir__) }

  before do
    FileUtils.rm_rf(dest)
    described_class.start([], destination_root: dest)
  end

  after { FileUtils.rm_rf(dest) }

  it "copies the inbox views into the host" do
    expect(File).to exist(File.join(dest, "app/views/instagram_connect/conversations/index.html.erb"))
    expect(File).to exist(File.join(dest, "app/views/instagram_connect/comments/index.html.erb"))
  end

  it "copies the engine layout" do
    expect(File).to exist(File.join(dest, "app/views/layouts/instagram_connect/application.html.erb"))
  end
end
