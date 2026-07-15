require "rails_helper"
require "fileutils"
require "generators/instagram_connect/controllers_generator"

RSpec.describe InstagramConnect::Generators::ControllersGenerator do
  let(:dest) { File.expand_path("../../tmp/controllers_dest", __dir__) }

  before do
    FileUtils.rm_rf(dest)
    described_class.start([], destination_root: dest)
  end

  after { FileUtils.rm_rf(dest) }

  it "copies the engine controllers into the host" do
    expect(File).to exist(File.join(dest, "app/controllers/instagram_connect/conversations_controller.rb"))
    expect(File).to exist(File.join(dest, "app/controllers/instagram_connect/webhooks_controller.rb"))
  end
end
