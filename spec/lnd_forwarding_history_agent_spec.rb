require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::LndForwardingHistoryAgent do
  before(:each) do
    @valid_options = Agents::LndForwardingHistoryAgent.new.default_options
    @checker = Agents::LndForwardingHistoryAgent.new(:name => "LndForwardingHistoryAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
