require "spec_helper"

RSpec.describe BuildSpecRunner do
  it "has a version number" do
    expect(BuildSpecRunner::VERSION).not_to be nil
  end
end
