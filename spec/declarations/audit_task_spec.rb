# frozen_string_literal: true

require "rails_helper"
require "rake"

# `rake tenancy_dable:audit` (DESIGN.md §16.3): status 0 and one stdout line when
# clean, status 1 with one finding per line on stderr otherwise.
RSpec.describe "rake tenancy_dable:audit" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("tenancy_dable:audit")
  end

  let(:task) { Rake::Task["tenancy_dable:audit"] }

  before { task.reenable }

  it "exits 0 and prints one line when every model declares its tenancy" do
    expect { task.invoke }
      .to output("tenancy_dable:audit: every model declares its tenancy\n").to_stdout
  end

  it "exits 1 with one finding per line on stderr" do
    stub_const("Forgotten", Class.new(ApplicationRecord) { self.table_name = "unindexed_records" })
    stub_const("LeakyGlobal", Class.new(ApplicationRecord) { self.table_name = "unindexed_records" })
    LeakyGlobal.tenant_global because: "x"

    expect {
      expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    }.to output(/\AForgotten: declares no tenancy.*\nLeakyGlobal: is declared tenant_global.*\z/m).to_stderr
  end

  it "can be invoked again after reenable" do
    expect { task.invoke }.to output(/every model declares/).to_stdout
    task.reenable
    expect { task.invoke }.to output(/every model declares/).to_stdout
  end
end
