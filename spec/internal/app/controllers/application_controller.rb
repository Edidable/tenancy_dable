# frozen_string_literal: true

# Base controller for the Combustion harness, mirroring a real Rails app. It
# descends from ActionController::Base, into which the railtie mixes
# TenancyDable::Controller::Resolvable on `:action_controller` load — so the
# `resolve_tenant!` macro is available to every controller below.
class ApplicationController < ActionController::Base
end
