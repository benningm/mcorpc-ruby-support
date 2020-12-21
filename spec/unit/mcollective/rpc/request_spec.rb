#!/usr/bin/env rspec

require 'spec_helper'

module MCollective
  module RPC
    describe Request do
      before(:each) do
        @req = {:msgtime        => Time.now,
                :senderid        => "spec test",
                :requestid       => "12345",
                :callerid        => "rip"}

        @req[:body] = {:action => "test",
                       :data   => {:foo => "bar", :process_results => true},
                       :agent  => "tester"}

        @ddl = DDL.new("rspec", :agent, false)

        @request = Request.new(@req, @ddl)
      end

      describe "#compatible_key" do
        it "should return the key if its a known key already" do
          expect(@request.compatible_key(:foo)).to be(:foo)
        end

        it "should return the symbol key if the DDL defines both" do
          @ddl.action("test", :description => "rspec")
          @ddl.instance_variable_set("@current_entity", "test")
          @ddl.input(:test, :prompt => "test", :description => "test", :type => :boolean, :optional => true)
          @ddl.input("test", :prompt => "test", :description => "test", :type => :boolean, :optional => true)

          expect(@request.compatible_key(:test)).to be(:test)
          expect(@request.compatible_key("test")).to eq("test")
        end

        it "should return the stringified key if a interned version of known string data was requested" do
          expect(@request.compatible_key(:string)).to eq(:string)
          @req[:body][:data]["string"] = "string data"
          expect(@request.compatible_key(:string)).to eq("string")
        end
      end

      describe "#validate!" do
        it "should validate the request using the supplied DDL" do
          @ddl.expects(:validate_rpc_request).with("test", {:foo => "bar", :process_results => true})
          @request.validate!
        end
      end

      describe "#initialize" do
        it "should set time" do
          expect(@request.time).to eq(@req[:msgtime])
        end

        it "should set action" do
          expect(@request.action).to eq("test")
        end

        it "should set data" do
          expect(@request.data).to eq({:foo => "bar", :process_results => true})
        end

        it "should set sender" do
          expect(@request.sender).to eq("spec test")
        end

        it "should set agent" do
          expect(@request.agent).to eq("tester")
        end

        it "should set uniqid" do
          expect(@request.uniqid).to eq("12345")
        end

        it "should set caller" do
          expect(@request.caller).to eq("rip")
        end

        it "should set unknown caller if none is supplied" do
          @req.delete(:callerid)
          expect(Request.new(@req, @ddl).caller).to eq("unknown")
        end

        it "should support JSON pure inputs" do
          @req[:body] = {"action" => "test",
                         "data"   => {"foo" => "bar", "process_results" => true},
                         "agent"  => "tester"}

          request = Request.new(@req, @ddl)

          expect(request.action).to eq("test")
          expect(request.agent).to eq("tester")
          expect(request.data).to eq("foo" => "bar", "process_results" => true)
        end
      end

      describe "#include?" do
        it "should correctly report on hash contents" do
          expect(@request.include?(:foo)).to eq(true)
        end

        it "should return false for non hash data" do
          @req[:body][:data] = "foo"
          expect(Request.new(@req, @ddl).include?(:foo)).to eq(false)
        end
      end

      describe "#should_respond?" do
        it "should return true if the header is absent" do
          @req[:body][:data].delete(:process_results)
          expect(Request.new(@req, @ddl).should_respond?).to eq(true)
        end

        it "should return correct value" do
          @req[:body][:data][:process_results] = false
          expect(Request.new(@req, @ddl).should_respond?).to eq(false)
          @req[:body][:data]["process_results"] = false
          expect(Request.new(@req, @ddl).should_respond?).to eq(false)
        end
      end

      describe "#[]" do
        it "should return nil for non hash data" do
          @req[:body][:data] = "foo"
          expect(Request.new(@req, @ddl)["foo"]).to eq(nil)
        end

        it "should return correct data" do
          expect(@request[:foo]).to eq("bar")
        end

        it "should return nil for absent data" do
          expect(@request[:bar]).to eq(nil)
        end
      end

      describe "#fetch" do
        it "should return nil for non hash data" do
          @req[:body][:data] = "foo"
          expect(Request.new(@req, @ddl)["foo"]).to eq(nil)
        end

        it "should fetch data with the correct default behavior" do
          expect(@request.fetch(:foo, "default")).to eq("bar")
          expect(@request.fetch(:rspec, "default")).to eq("default")
        end
      end

      describe "#to_hash" do
        it "should have the correct keys" do
          expect(@request.to_hash.keys.sort).to eq([:action, :agent, :data])
        end

        it "should return the correct agent" do
          expect(@request.to_hash[:agent]).to eq("tester")
        end

        it "should return the correct action" do
          expect(@request.to_hash[:action]).to eq("test")
        end

        it "should return the correct data" do
          expect(@request.to_hash[:data]).to eq({:foo => "bar",
                                             :process_results => true})
        end
      end
    end
  end
end

