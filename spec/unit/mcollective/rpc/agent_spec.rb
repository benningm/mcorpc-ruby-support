#!/usr/bin/env rspec

require 'spec_helper'

module MCollective
  module RPC
    describe Agent do
      before do
        ddl = stub
        ddl.stubs(:meta).returns({})
        ddl.stubs(:action).returns([])
        ddl.stubs(:validate_rpc_request).returns(true)
        DDL.stubs(:new).returns(ddl)

        @agent = Agent.new
        @agent.reply = {}
        @agent.request = {}
      end

      describe "#handlemsg" do
        before do
          Reply.any_instance.stubs(:initialize_data)

          @agent.stubs(:respond_to?).with("rspec_action_action").returns(true)
          @agent.stubs(:respond_to?).with("authorization_hook").returns(false)
          @agent.stubs(:rspec_action_action).returns(nil)

          @msg = {:msgtime => 1356006671,
                  :senderid => "example.com",
                  :requestid => "55f8abe1442328321667877a08bdc586",
                  :body => {:agent => "rspec_agent",
                            :action => "rspec_action",
                            :data => {}},
                  :caller => "cert=rspec"}
        end

        it "should or validate the incoming request" do
          Request.any_instance.expects(:validate!).raises(DDLValidationError, "Failed to validate")

          reply = @agent.handlemsg(@msg, DDL.new)

          expect(reply[:statuscode]).to eq(4)
          expect(reply[:statusmsg]).to eq("Failed to validate")
        end

        it "should call the authorization hook if set" do
          @agent.expects(:respond_to?).with("authorization_hook").returns(true)
          @agent.expects(:authorization_hook).raises("authorization denied")
          Log.stubs(:error)

          reply = @agent.handlemsg(@msg, DDL.new)

          expect(reply[:statuscode]).to eq(5)
          expect(reply[:statusmsg]).to eq("authorization denied")
        end

        it "should audit the request" do
          @agent.expects(:audit_request)

          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(0)
        end

        it "should call the before_processing_hook" do
          @agent.expects(:before_processing_hook)

          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(0)
        end

        it "should fail if the action does not exist" do
          @agent.expects(:respond_to?).with("rspec_action_action").returns(false)
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(2)
        end

        it "should call the action correctly" do
          @agent.expects(:rspec_action_action)
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(0)
        end

        it "should handle RPC Aborted errors" do
          @agent.expects(:rspec_action_action).raises(RPCAborted, "rspec test")
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(1)
          expect(reply[:statusmsg]).to eq("rspec test")
        end

        it "should handle Unknown Action errors" do
          @agent.stubs(:respond_to?).with("rspec_action_action").returns(false)
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(2)
          expect(reply[:statusmsg]).to eq("Unknown action 'rspec_action' for agent 'rspec_agent'")
        end

        it "should handle Missing Data errors" do
          @agent.expects(:rspec_action_action).raises(MissingRPCData, "rspec test")
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(3)
          expect(reply[:statusmsg]).to eq("rspec test")
        end

        it "should handle Invalid Data errors" do
          @agent.expects(:rspec_action_action).raises(InvalidRPCData, "rspec test")
          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(4)
          expect(reply[:statusmsg]).to eq("rspec test")
        end

        it "should handle unknown errors" do
          @agent.expects(:rspec_action_action).raises(UnknownRPCError, "rspec test")
          Log.expects(:error).twice

          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(5)
          expect(reply[:statusmsg]).to eq("rspec test")
        end

        it "should handle arbitrary exceptions" do
          @agent.expects(:rspec_action_action).raises(Exception, "rspec test")
          Log.expects(:error).twice

          reply = @agent.handlemsg(@msg, DDL.new)
          expect(reply[:statuscode]).to eq(5)
          expect(reply[:statusmsg]).to eq("rspec test")
        end

        it "should call the after_processing_hook" do
          @agent.expects(:after_processing_hook)
          reply = @agent.handlemsg(@msg, DDL.new)
        end

        it "should respond if required" do
          Request.any_instance.expects(:should_respond?).returns(true)
          Reply.any_instance.expects(:to_hash).returns({})
          expect(@agent.handlemsg(@msg, DDL.new)).to eq({})
        end

        it "should not respond when not required" do
          Request.any_instance.expects(:should_respond?).returns(false)
          Reply.any_instance.expects(:to_hash).never
          expect(@agent.handlemsg(@msg, DDL.new)).to eq(nil)
        end
      end

      describe "#meta" do
        it "should be deprecated" do
          Log.expects(:warn).with(regexp_matches(/Setting metadata in agents has been deprecated/))
          Agent.metadata("foo")
        end
      end

      describe "#activate?" do
        class Test < MCollective::RPC::Agent;end

        let(:config) do
          conf = mock
          conf.stubs(:pluginconf).returns({})
          conf
        end

        before(:each) do
          Config.stubs(:instance).returns(config)
          Log.stubs(:debug)
        end

        it "should return true if plugins are globally enabled" do
          config.stubs(:activate_agents).returns(true)
          expect(Test.activate?).to eq(true)
        end

        it "should return true if plugins are globally disabled but locally enabled" do
          config.stubs(:activate_agents).returns(false)
          config.pluginconf['test.activate_agent'] = true
          expect(Test.activate?).to eq(true)
        end

        it "should return false if plugins are globally disabled" do
          config.stubs(:activate_agents).returns(false)
          expect(Test.activate?).to eq(false)
        end

        it "should return false if plugins are globally enabled but locally disabled" do
          config.stubs(:activate_agents).returns(true)
          config.pluginconf['test.activate_agent'] = false
          expect(Test.activate?).to eq(false)
        end
      end

      describe "#load_ddl" do
        it "should load the correct DDL" do
          ddl = stub
          ddl.stubs(:meta).returns({:timeout => 5})

          DDL.expects(:new).with("agent", :agent).returns(ddl)

          expect(Agent.new.timeout).to eq(5)
        end

        it "should fail if the DDL isn't loaded" do
          DDL.expects(:new).raises("failed to load")
          Log.expects(:error).once
          expect { Agent.new }.to raise_error(DDLValidationError)
        end

        it "should default to 10 second timeout" do
          ddl = stub
          ddl.stubs(:meta).returns({})

          DDL.expects(:new).with("agent", :agent).returns(ddl)

          expect(Agent.new.timeout).to eq(10)
        end
      end

      describe "#run" do
        before do
          @status = mock
          @status.stubs(:exitstatus).returns(0)
          @shell = mock
          @shell.stubs(:runcommand)
          @shell.stubs(:status).returns(@status)
        end

        it "should accept stderr and stdout and force them to be strings" do
          Shell.expects(:new).with("rspec", {:stderr => "", :stdout => ""}).returns(@shell)
          @agent.send(:run, "rspec", {:stderr => :err, :stdout => :out})
          expect(@agent.reply[:err]).to eq("")
          expect(@agent.reply[:out]).to eq("")
        end

        it "should accept existing variables for stdout and stderr and fail if they dont support <<" do
          @agent.reply[:err] = "err"
          @agent.reply[:out] = "out"

          Shell.expects(:new).with("rspec", {:stderr => "err", :stdout => "out"}).returns(@shell)
          @agent.send(:run, "rspec", {:stderr => @agent.reply[:err], :stdout => @agent.reply[:out]})
          expect(@agent.reply[:err]).to eq("err")
          expect(@agent.reply[:out]).to eq("out")

          @agent.reply.expects("fail!").with("stderr should support << while calling run(rspec)").raises("stderr fail")
          expect { @agent.send(:run, "rspec", {:stderr => nil, :stdout => ""}) }.to raise_error("stderr fail")

          @agent.reply.expects("fail!").with("stdout should support << while calling run(rspec)").raises("stdout fail")
          expect { @agent.send(:run, "rspec", {:stderr => "", :stdout => nil}) }.to raise_error("stdout fail")
        end

        it "should set stdin, cwd and environment if supplied" do
          Shell.expects(:new).with("rspec", {:stdin => "stdin", :cwd => "cwd", :environment => "env"}).returns(@shell)
          @agent.send(:run, "rspec", {:stdin => "stdin", :cwd => "cwd", :environment => "env"})
        end

        it "should ignore unknown options" do
          Shell.expects(:new).with("rspec", {}).returns(@shell)
          @agent.send(:run, "rspec", {:rspec => "rspec"})
        end

        it "should chomp strings if configured to do so" do
          Shell.expects(:new).with("rspec", {:stderr => 'err', :stdout => 'out'}).returns(@shell)

          @agent.reply[:err] = "err"
          @agent.reply[:out] = "out"

          @agent.reply[:err].expects("chomp!")
          @agent.reply[:out].expects("chomp!")

          @agent.send(:run, "rspec", {:chomp => true, :stdout => @agent.reply[:out], :stderr => @agent.reply[:err]})
        end

        it "should return the exitstatus" do
          Shell.expects(:new).with("rspec", {}).returns(@shell)
          expect(@agent.send(:run, "rspec", {})).to eq(0)
        end

        it "should handle nil from the shell handler" do
          @shell.expects(:status).returns(nil)
          Shell.expects(:new).with("rspec", {}).returns(@shell)
          expect(@agent.send(:run, "rspec", {})).to eq(-1)
        end
      end

      describe "#validate" do
        it "should detect missing data" do
          @agent.request = {}
          expect { @agent.send(:validate, :foo, String) }.to raise_error(MissingRPCData, "please supply a foo argument")
        end

        it "should catch validation errors and turn them into use case specific ones" do
          @agent.request = {:input_key => "should be a number"}
          Validator.expects(:validate).raises(ValidatorError, "input_key should be a number")
          expect { @agent.send(:validate, :input_key, :number) }.to raise_error("Input input_key did not pass validation: input_key should be a number")
        end
      end
    end
  end
end
