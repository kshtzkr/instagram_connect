require "rails_helper"

RSpec.describe InstagramConnect::SyncConversationsJob do
  let(:base) { "https://graph.facebook.com/v21.0" }
  let(:json) { { "Content-Type" => "application/json" } }

  let!(:account) do
    InstagramConnect::Account.create!(ig_user_id: "US", auth_path: "facebook_login",
                                      access_token: "tok", page_id: "PAGE1", active: true)
  end

  def stub_threads(ids)
    stub_request(:get, "#{base}/PAGE1/conversations").with(query: hash_including({}))
      .to_return(status: 200, body: { data: ids.map { |id| { id: id } } }.to_json, headers: json)
  end

  def stub_messages(conversation_id, messages)
    stub_request(:get, "#{base}/#{conversation_id}").with(query: hash_including({}))
      .to_return(status: 200, body: { messages: { data: messages } }.to_json, headers: json)
  end

  def inbound(id:, text:, at: "2026-07-25T10:00:00+0000")
    { id: id, created_time: at, message: text,
      from: { id: "CUST" }, to: { data: [ { id: "US" } ] } }
  end

  def outbound(id:, text:, at: "2026-07-25T11:00:00+0000")
    { id: id, created_time: at, message: text,
      from: { id: "US" }, to: { data: [ { id: "CUST" } ] } }
  end

  it "imports an existing thread and its messages" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ outbound(id: "M2", text: "sure, sending it over"),
                          inbound(id: "M1", text: "how much for Ladakh?") ])

    described_class.perform_now(account.id)

    conversation = InstagramConnect::Conversation.find_by(igsid: "CUST")
    expect(conversation).to be_present
    expect(conversation.messages.pluck(:body))
      .to contain_exactly("how much for Ladakh?", "sure, sending it over")
  end

  # Meta returns messages newest-first; replaying them in that order would leave
  # the thread summary showing the oldest message.
  it "leaves the newest message as the thread preview" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ outbound(id: "M2", text: "newest", at: "2026-07-25T11:00:00+0000"),
                          inbound(id: "M1", text: "oldest", at: "2026-07-25T10:00:00+0000") ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Conversation.find_by(igsid: "CUST").last_message_preview).to eq("newest")
  end

  it "marks direction from who sent it" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "M1", text: "hi"), outbound(id: "M2", text: "hello") ])

    described_class.perform_now(account.id)

    messages = InstagramConnect::Message.order(:ig_message_id)
    expect(messages.find_by(ig_message_id: "M1").direction).to eq("inbound")
    expect(messages.find_by(ig_message_id: "M2").direction).to eq("outbound")
  end

  # Re-running must not duplicate: an operator can trigger this whenever, and it
  # also races the webhook that may deliver the same message.
  it "is safe to run twice" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "M1", text: "hi") ])

    described_class.perform_now(account.id)
    described_class.perform_now(account.id)

    expect(InstagramConnect::Message.count).to eq(1)
  end

  it "skips a thread with no readable messages rather than creating an empty row" do
    stub_threads([ "T1" ])
    stub_messages("T1", [])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Conversation.count).to eq(0)
  end

  # The conversations edge belongs to the Page on the Facebook-Login path —
  # aiming it at the Instagram user id fails with a capability error, which is
  # exactly what happened in production.
  it "lists conversations from the Page, not the Instagram user" do
    stub_threads([])

    described_class.perform_now(account.id)

    expect(WebMock).to have_requested(:get, "#{base}/PAGE1/conversations")
      .with(query: hash_including("platform" => "instagram"))
  end

  it "falls back to the Instagram user id when there is no Page" do
    account.update!(page_id: nil)
    stub_request(:get, "#{base}/US/conversations").with(query: hash_including({}))
      .to_return(status: 200, body: { data: [] }.to_json,
                 headers: { "Content-Type" => "application/json" })

    described_class.perform_now(account.id)

    expect(WebMock).to have_requested(:get, "#{base}/US/conversations")
      .with(query: hash_including({}))
  end

  # Silence here cost a production afternoon: the job "succeeded" in 600ms and
  # imported nothing, and every screen said nothing had failed.
  it "says WHY when the listing fails" do
    stub_request(:get, "#{base}/PAGE1/conversations").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "capability denied" } }.to_json,
                 headers: { "Content-Type" => "application/json" })
    allow(described_class.logger).to receive(:error)

    described_class.perform_now(account.id)

    expect(described_class.logger).to have_received(:error)
      .with(a_string_including("capability denied"))
  end

  # Meta prices the conversations edge per row and refuses pages it finds too
  # heavy, with "Please reduce the amount of data you're asking for". A Page
  # with deep Messenger history refused 20; the client retries once at the
  # smallest useful page rather than giving up.
  it "retries with a tiny page when Meta says reduce the data" do
    stub_request(:get, "#{base}/PAGE1/conversations")
      .with(query: hash_including("limit" => "10"))
      .to_return(status: 400,
                 body: { error: { message: "Please reduce the amount of data you're asking for, then retry your request" } }.to_json,
                 headers: json)
    stub_request(:get, "#{base}/PAGE1/conversations")
      .with(query: hash_including("limit" => "2"))
      .to_return(status: 200, body: { data: [ { id: "T1" } ] }.to_json, headers: json)
    stub_messages("T1", [ inbound(id: "M1", text: "hi") ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Message.find_by(ig_message_id: "M1")).to be_present
  end

  it "does nothing when the thread listing fails" do
    stub_request(:get, "#{base}/PAGE1/conversations").with(query: hash_including({}))
      .to_return(status: 400, body: { error: { message: "nope" } }.to_json, headers: json)

    expect { described_class.perform_now(account.id) }.not_to change(InstagramConnect::Conversation, :count)
  end

  it "skips a thread whose messages cannot be read" do
    stub_threads([ "T1" ])
    stub_request(:get, "#{base}/T1").with(query: hash_including({}))
      .to_return(status: 403, body: { error: { message: "no" } }.to_json, headers: json)

    expect { described_class.perform_now(account.id) }.not_to change(InstagramConnect::Conversation, :count)
  end

  it "ignores a message with no id" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "", text: "hi") ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Message.count).to eq(0)
  end

  # Time.zone.parse has two failure modes and only one of them raises: garbage
  # returns nil quietly, an impossible date raises. Both have to land as nil
  # rather than taking the sync down.
  it "survives a timestamp it cannot read at all" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "M1", text: "hi", at: "not a time") ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Message.find_by(ig_message_id: "M1").sent_at).to be_nil
  end

  it "survives a timestamp that raises" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "M1", text: "hi", at: "2026-13-45T99:99:99") ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Message.find_by(ig_message_id: "M1").sent_at).to be_nil
  end

  # A thread where we are the only participant Meta reports still has to land
  # somewhere rather than blow up.
  it "falls back to our own id when no counterpart is named" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ { id: "M1", created_time: "2026-07-25T10:00:00+0000",
                            message: "note", from: { id: "US" }, to: { data: [] } } ])

    described_class.perform_now(account.id)

    expect(InstagramConnect::Conversation.find_by(igsid: "US")).to be_present
  end

  # A webhook can deliver the same message while this is mid-import; the unique
  # index is what actually prevents the duplicate, and losing the race is fine.
  it "yields to a webhook that wrote the same message first" do
    stub_threads([ "T1" ])
    stub_messages("T1", [ inbound(id: "M1", text: "hi") ])
    allow_any_instance_of(InstagramConnect::Message)
      .to receive(:save!).and_raise(ActiveRecord::RecordNotUnique.new("dup"))

    expect { described_class.perform_now(account.id) }.not_to raise_error
    # Proves the raise really happened and was swallowed, rather than the stub
    # silently not applying and the assertion passing for the wrong reason.
    expect(InstagramConnect::Message.count).to eq(0)
  end

  it "does nothing for an account that is gone or inactive" do
    account.update!(active: false)

    expect { described_class.perform_now(account.id) }.not_to change(InstagramConnect::Conversation, :count)
    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
