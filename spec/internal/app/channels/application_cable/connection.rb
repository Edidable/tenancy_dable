# frozen_string_literal: true

# HARNESS-ONLY — NOT gem code. Mirrors a real host app's Cable connection to
# document the single host requirement and keep the Combustion app faithful.
#
# The gem deliberately does NOT own Cable authentication (a v0.3.0 guardrail):
# establishing the connection identity is the host's job. A host declares
# `identified_by :current_user` and sets it however it authenticates
# (cookie/session/token); `TenancyDable::Channel` only READS `current_user` off
# the connection (Action Cable exposes each `identified_by` attribute as a
# delegated reader on the channel). That one line is the entire contract.
#
# The channel specs inject identity with `stub_connection(current_user: …)` and
# therefore never invoke `#connect` — it "trusts a test-provided identifier"
# precisely because connection-level auth is the host's concern, not the gem's,
# and is out of scope for these specs.
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      User.find_by(id: request.params[:user_id])
    end
  end
end
