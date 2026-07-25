require "rails_helper"

RSpec.describe InstagramConnect::ApplicationController do
  # A concrete engine controller — ApplicationController is abstract, and these
  # are the two host-facing seams every engine screen runs through.
  let(:controller) { InstagramConnect::ConversationsController.new }

  describe "layout selection" do
    it "uses the engine's own layout when the host does not inherit" do
      InstagramConnect.configuration.inherit_host_layout = false

      expect(controller.send(:instagram_connect_layout)).to eq("instagram_connect/application")
    end

    it "uses the host's application layout when the host opts in" do
      InstagramConnect.configuration.inherit_host_layout = true

      expect(controller.send(:instagram_connect_layout)).to eq("application")
    end
  end

  describe "#instagram_connect_user_id" do
    it "returns nil when the host configured no resolver" do
      InstagramConnect.configuration.current_user_id_resolver = nil

      expect(controller.send(:instagram_connect_user_id)).to be_nil
    end

    it "evaluates the host's resolver in the controller's context" do
      InstagramConnect.configuration.current_user_id_resolver = -> { 42 }

      expect(controller.send(:instagram_connect_user_id)).to eq(42)
    end
  end

  describe "#authenticate_instagram_connect!" do
    it "does nothing when the host configured no authentication hook" do
      InstagramConnect.configuration.authenticate_with = nil

      expect { controller.send(:authenticate_instagram_connect!) }.not_to raise_error
    end

    it "evaluates the host's hook in the controller's context" do
      seen = nil
      InstagramConnect.configuration.authenticate_with = -> { seen = self }

      controller.send(:authenticate_instagram_connect!)

      expect(seen).to be(controller)
    end
  end
end
