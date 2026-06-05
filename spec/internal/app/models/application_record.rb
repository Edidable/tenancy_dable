# frozen_string_literal: true

# Base class for the harness's host models, mirroring a real Rails app.
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
