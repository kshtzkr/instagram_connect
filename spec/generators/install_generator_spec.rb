require "rails_helper"
require "fileutils"
require "generators/instagram_connect/install/install_generator"

RSpec.describe InstagramConnect::Generators::InstallGenerator do
  let(:dest) { File.expand_path("../../tmp/generator_dest", __dir__) }

  before do
    FileUtils.rm_rf(dest)
    FileUtils.mkdir_p(File.join(dest, "config"))
    File.write(File.join(dest, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
    described_class.start([], destination_root: dest)
  end

  after { FileUtils.rm_rf(dest) }

  it "writes the initializer" do
    path = File.join(dest, "config/initializers/instagram_connect.rb")
    expect(File).to exist(path)
    expect(File.read(path)).to include("InstagramConnect.configure")
  end

  it "mounts the engine in the host routes" do
    expect(File.read(File.join(dest, "config/routes.rb")))
      .to include('mount InstagramConnect::Engine => "/instagram"')
  end

  it "does not copy migrations into the host (the gem owns them)" do
    expect(Dir[File.join(dest, "db/migrate/*")]).to be_empty
  end
end
