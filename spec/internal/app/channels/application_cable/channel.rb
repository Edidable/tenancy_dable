# frozen_string_literal: true

# HARNESS-ONLY base channel, mirroring a real host app's
# `ApplicationCable::Channel`. Tenant-aware channels (e.g. TenantChannel) descend
# from it and `include TenancyDable::Channel`.
module ApplicationCable
  class Channel < ActionCable::Channel::Base
  end
end
