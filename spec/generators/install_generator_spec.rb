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

  it "copies the five table migrations" do
    migrations = Dir[File.join(dest, "db/migrate/*_create_instagram_connect_*.rb")]
    expect(migrations.size).to eq(5)

    accounts = migrations.find { |f| f.include?("accounts") }
    expect(File.read(accounts)).to include("create_table :instagram_connect_accounts")
  end
end
