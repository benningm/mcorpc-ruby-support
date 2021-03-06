#!/usr/bin/env rspec

require 'spec_helper'

module MCollective
  module RPC
    describe Stats do
      before(:each) do
        @expected = {:discoverytime => 0,
                     :okcount => 0,
                     :blocktime => 0,
                     :failcount => 0,
                     :noresponsefrom => [],
                     :unexpectedresponsefrom => [],
                     :responses => 0,
                     :totaltime => 0,
                     :discovered => 0,
                     :starttime => 1300031826.0,
                     :requestid => nil,
                     :aggregate_summary => [],
                     :aggregate_failures => [],
                     :discovered_nodes => []}

        @stats = Stats.new
      end

      describe "#initialize" do
        it "should reset stats on creation" do
          Stats.any_instance.stubs(:reset).returns(true).once
          s = Stats.new
        end
      end

      describe "#reset" do
        it "should initialize data correctly" do
          Time.stubs(:now).returns(Time.at(1300031826))
          s = Stats.new

          @expected.keys.each do |k|
            expect(@expected[k]).to eq(s.send(k))
          end
        end
      end

      describe "#to_hash" do
        it "should return correct stats" do
          Time.stubs(:now).returns(Time.at(1300031826))
          s = Stats.new

          expect(s.to_hash).to eq(@expected)
        end
      end

      describe "#[]" do
        it "should return stat values" do
          Time.stubs(:now).returns(Time.at(1300031826))
          s = Stats.new

          @expected.keys.each do |k|
            expect(@expected[k]).to eq(s[k])
          end
        end

        it "should return nil for unknown values" do
          expect(@stats["foo"]).to eq(nil)
        end
      end

      describe "#ok" do
        it "should increment stats" do
          @stats.ok
          expect(@stats[:okcount]).to eq(1)
        end
      end

      describe "#fail" do
        it "should increment stats" do
          @stats.fail
          expect(@stats.failcount).to eq(1)
        end
      end

      describe "#time_discovery" do
        it "should set start time correctly" do
          Time.stubs(:now).returns(Time.at(1300031826))

          @stats.time_discovery(:start)

          expect(@stats.instance_variable_get("@discovery_start")).to eq(1300031826.0)
        end

        it "should record the difference correctly" do
          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_discovery(:end)

          expect(@stats.discoverytime).to eq(1.0)
        end

        it "should handle unknown actions and set discovery time to 0" do
          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_discovery(:stop)

          expect(@stats.discoverytime).to eq(0)
        end

      end

      describe "#client_stats=" do
        it "should store stats correctly" do
          data = {}
          keys = [:noresponsefrom, :unexpectedresponsefrom, :responses, :starttime, :blocktime, :totaltime, :discoverytime]
          keys.each {|k| data[k] = k}

          @stats.client_stats = data

          keys.each do |k|
            expect(@stats[k]).to eq(data[k])
          end
        end

        it "should not store discovery time if it was already stored" do
          data = {}
          keys = [:noresponsefrom, :unexpectedresponsefrom, :responses, :starttime, :blocktime, :totaltime, :discoverytime]
          keys.each {|k| data[k] = k}

          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_discovery(:end)

          dtime = @stats.discoverytime

          @stats.client_stats = data

          expect(@stats.discoverytime).to eq(dtime)
        end
      end

      describe "#time_block_execution" do
        it "should set start time correctly" do
          Time.stubs(:now).returns(Time.at(1300031826))

          @stats.time_block_execution(:start)

          expect(@stats.instance_variable_get("@block_start")).to eq(1300031826.0)
        end

        it "should record the difference correctly" do
          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:end)

          expect(@stats.blocktime).to eq(1)
        end

        it "should handle unknown actions and set discovery time to 0" do
          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:stop)

          expect(@stats.blocktime).to eq(0)
        end
      end

      describe "#discovered_agents" do
        it "should set discovered_nodes" do
          nodes = ["one", "two"]
          @stats.discovered_agents(nodes)
          expect(@stats.discovered_nodes).to eq(nodes)
        end

        it "should set discovered count" do
          nodes = ["one", "two"]
          @stats.discovered_agents(nodes)
          expect(@stats.discovered).to eq(2)
        end
      end

      describe "#finish_request" do
        it "should calculate totaltime correctly" do
          Time.stubs(:now).returns(Time.at(1300031824))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031825))
          @stats.time_discovery(:end)

          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:end)

          @stats.discovered_agents(["one", "two", "three"])
          @stats.node_responded("one")
          @stats.node_responded("two")

          @stats.finish_request

          expect(@stats.totaltime).to eq(2)
        end

        it "should calculate no responses correctly" do
          Time.stubs(:now).returns(Time.at(1300031824))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031825))
          @stats.time_discovery(:end)

          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:end)

          @stats.discovered_agents(["one", "two", "three"])
          @stats.node_responded("one")
          @stats.node_responded("two")

          @stats.finish_request

          expect(@stats.noresponsefrom).to eq(["three"])
        end

        it "should calculate unexpected responses correctly" do
          Time.stubs(:now).returns(Time.at(1300031824))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031825))
          @stats.time_discovery(:end)

          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:end)

          @stats.discovered_agents(["one", "two"])
          @stats.node_responded("three")
          @stats.node_responded("one")
          @stats.node_responded("two")

          @stats.finish_request

          expect(@stats.unexpectedresponsefrom).to eq(["three"])
        end

        it "should recover from failure correctly" do
          Time.stubs(:now).returns(Time.at(1300031824))
          @stats.time_discovery(:start)

          Time.stubs(:now).returns(Time.at(1300031825))
          @stats.time_discovery(:end)

          Time.stubs(:now).returns(Time.at(1300031826))
          @stats.time_block_execution(:start)

          Time.stubs(:now).returns(Time.at(1300031827))
          @stats.time_block_execution(:end)

          # cause the .each to raise an exception
          @stats.instance_variable_set("@responsesfrom", nil)
          @stats.finish_request

          expect(@stats.noresponsefrom).to eq([])
          expect(@stats.unexpectedresponsefrom).to eq([])
          expect(@stats.totaltime).to eq(0)
        end
      end

      describe "#node_responded" do
        it "should append to the list of nodes" do
          @stats.node_responded "foo"
          expect(@stats.responsesfrom).to eq(["foo"])
        end

        it "should create a new array if adding fails" do
          # cause the << to fail
          @stats.instance_variable_set("@responsesfrom", nil)

          @stats.node_responded "foo"
          expect(@stats.responsesfrom).to eq(["foo"])
        end
      end

      describe "#no_response_report" do
        it "should create an empty report if all nodes responded" do
          @stats.discovered_agents ["foo"]
          @stats.node_responded "foo"
          @stats.finish_request

          expect(@stats.no_response_report).to eq("")
        end

        it "should list all nodes that did not respond" do
          @stats.discovered_agents ["foo", "bar"]
          @stats.finish_request

          expect(@stats.no_response_report).to match(Regexp.new(/No response from.+bar\s+foo/m))
        end
      end

      describe "#unexpected_response_report" do
        it "should create an empty report if all responding nodes were discovered" do
          @stats.discovered_agents ["foo"]
          @stats.node_responded "foo"
          @stats.finish_request

          expect(@stats.unexpected_response_report).to eq("")
        end

        it "should list all nodes that did not respond" do
          @stats.discovered_agents []
          @stats.node_responded "foo"
          @stats.node_responded "bar"
          @stats.finish_request

          expect(@stats.unexpected_response_report).to match(Regexp.new(/Unexpected response from.+bar\s+foo/m))
        end
      end

      describe "#text_for_aggregates" do
        let(:aggregate){mock()}

        before :each do
          aggregate.stubs(:result).returns({:output => "success"})
          aggregate.stubs(:action).returns("action")
        end

        it "should create the correct output text for aggregate functions" do
          @stats.aggregate_summary = [aggregate]
          aggregate.stubs(:is_a?).returns(true)
          expect(@stats.text_for_aggregates).to match(/Summary of.*/)
        end

        it "should display an error message for a failed statup hook" do
          @stats.aggregate_failures = [{:name => "rspec", :type => :startup}]
          expect(@stats.text_for_aggregates).to match(/exception raised while processing startup hook/)
        end

        it "should display an error message for an unspecified output" do
          @stats.aggregate_failures = [{:name => "rspec", :type => :create}]
          expect(@stats.text_for_aggregates).to match(/unspecified output 'rspec' for the action/)
        end

        it "should display an error message for a failed process_result" do
          @stats.aggregate_failures = [{:name => "rspec", :type => :process_result}]
          expect(@stats.text_for_aggregates).to match(/exception raised while processing result data/)
        end

        it "should display an error message for a failed summarize" do
          @stats.aggregate_failures = [{:name => "rspec", :type => :summarize}]
          expect(@stats.text_for_aggregates).to match(/exception raised while summarizing/)
        end
      end
    end
  end
end
