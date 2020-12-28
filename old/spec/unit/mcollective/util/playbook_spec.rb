require "spec_helper"
require "mcollective/util/playbook"

module MCollective
  module Util
    describe Playbook do
      let(:playbook) { Playbook.new }
      let(:nodes) { playbook.instance_variable_get("@nodes") }
      let(:tasks) { playbook.instance_variable_get("@tasks") }
      let(:uses) { playbook.instance_variable_get("@uses") }
      let(:inputs) { playbook.instance_variable_get("@inputs") }
      let(:stores) { playbook.instance_variable_get("@data_stores") }
      let(:playbook_fixture) { YAML.load(File.read("spec/fixtures/playbooks/playbook.yaml")) }

      describe "#validate_configuration!" do
        let(:security) { stub(:valid_callerid? => false) }
        let(:extra_keys) { YAML.load(File.read("spec/fixtures/playbooks/illegal.yaml")) }

        before(:each) do
          PluginManager.expects(:[]).with("security_plugin").returns(security)
        end

        it "should detect invalid keys" do
          playbook.from_hash(extra_keys)
          Log.expects(:error).with("Invalid playbook data items foo found")
          Log.expects(:error).with("A playbook name is needed")
          Log.expects(:error).with("A playbook version is needed")
          Log.expects(:error).with("A playbook author is needed")
          Log.expects(:error).with("A playbook description is needed")
          Log.expects(:error).with("Invalid log level illegal, valid levels are debug, info, warn, error, fatal")
          Log.expects(:error).with("Invalid callerid rspec")
          Log.expects(:error).with("uses should be a hash")
          Log.expects(:error).with("nodes should be a hash")
          Log.expects(:error).with("hooks should be a hash")
          Log.expects(:error).with("data_stores should be a hash")
          Log.expects(:error).with("inputs should be a hash")
          Log.expects(:error).with("locks should be a array")
          Log.expects(:error).with("tasks should be a array")

          expect { playbook.validate_configuration! }.to raise_error("Playbook is not in a valid format")
        end

        it "should allow valid playbooks" do
          playbook.from_hash(playbook_fixture)
          security.expects(:valid_callerid?).returns(true)
          playbook.validate_configuration!
        end
      end

      describe "#release_playbook_locks" do
        it "should lock all the locks" do
          playbook.from_hash(playbook_fixture)

          stores.expects(:release).with("mem_store/choria/locks/playbook/test_playbook")
          stores.expects(:release).with("mem_store/playbook")

          playbook.release_playbook_locks
        end
      end

      describe "#obtain_playbook_locks" do
        it "should lock all the locks" do
          playbook.from_hash(playbook_fixture)

          stores.expects(:lock).with("mem_store/choria/locks/playbook/test_playbook")
          stores.expects(:lock).with("mem_store/playbook")

          playbook.obtain_playbook_locks
        end
      end

      describe "#lock_path" do
        it "should construct the correct path" do
          playbook.from_hash(playbook_fixture)
          expect(playbook.lock_path("rspec/key")).to eq("rspec/key")
          expect(playbook.lock_path("rspec")).to eq("rspec/choria/locks/playbook/test_playbook")
        end
      end
      describe "#static_inputs" do
        it "should get the right inputs" do
          inputs.expects(:static_keys).returns(["s1"])
          expect(playbook.static_inputs).to eq(["s1"])
        end
      end

      describe "#dynamic_inputs" do
        it "should get the right inputs" do
          inputs.expects(:dynamic_keys).returns(["dynamic1"])
          expect(playbook.dynamic_inputs).to eq(["dynamic1"])
        end
      end

      describe "#prepare_data_stores" do
        it "should prepare data sources with the right data" do
          playbook.from_hash(playbook_fixture)
          playbook.expects(:t).with(playbook_fixture["data_stores"]).returns(playbook_fixture["data_stores"])
          stores.expects(:from_hash).with(playbook_fixture["data_stores"]).returns(stores)
          stores.expects(:prepare)
          playbook.prepare_data_stores
        end
      end

      describe "#task_results" do
        it "should delegate to tasks" do
          tasks.expects(:results).returns(results = [])
          expect(playbook.task_results).to be(results)
        end
      end

      describe "#previous_task_result" do
        it "should fetch the last result" do
          tasks.results << stub
          tasks.results << stub
          tasks.results << stub

          expect(playbook.previous_task_result).to be(tasks.results.last)
        end
      end

      describe "#previous_task" do
        let(:task) { {:description => "rspec"} }
        let(:result) { Playbook::TaskResult.new(task) }

        before(:each) do
          playbook.stubs(:previous_task_result).returns(result)
        end

        context "when there are no results" do
          before(:each) { playbook.stubs(:previous_task_result).returns(nil) }

          it "should support properties" do
            expect(playbook.previous_task("success")).to be(false)
            expect(playbook.previous_task("msg")).to eq("No previous task were found")
            expect(playbook.previous_task("message")).to eq("No previous task were found")
            expect(playbook.previous_task("data")).to eq([])
          end
        end

        context "when the result did not run" do
          before(:each) do
            result.ran = false
          end

          it "should support properties" do
            expect(playbook.previous_task("success")).to be(false)
            expect(playbook.previous_task("msg")).to eq("Previous task did not run")
            expect(playbook.previous_task("message")).to eq("Previous task did not run")
            expect(playbook.previous_task("data")).to eq([])
          end
        end

        context "when the result ran" do
          before(:each) do
            result.ran = true
            result.success = true
            result.msg = "rspec message"
            result.data = [:rspec]
            result.stubs(:run_time).returns(1.11111)
            result.task = {:description => "rspec description"}
          end

          it "should support properties" do
            expect(playbook.previous_task("success")).to be(true)
            expect(playbook.previous_task("msg")).to eq("rspec message")
            expect(playbook.previous_task("message")).to eq("rspec message")
            expect(playbook.previous_task("data")).to eq([:rspec])
            expect(playbook.previous_task("description")).to eq("rspec description")
            expect(playbook.previous_task("runtime")).to eq(1.11)
          end
        end
      end

      describe "#seconds_to_human" do
        it "should correctly convert seconds" do
          expect(playbook.seconds_to_human(60 * 60 * 24 + (60 * 61 + 1))).to eq("1 day 1 hours 1 minutes 01 seconds")
          expect(playbook.seconds_to_human(60 * 60 * 12 + (60 * 61 + 1))).to eq("13 hours 1 minutes 01 seconds")
          expect(playbook.seconds_to_human(61)).to eq("1 minutes 01 seconds")
        end
      end

      describe "#in_context" do
        it "should set and restore context" do
          playbook.context = "rspec"
          playbook.in_context("foo") do
            expect(playbook.context).to eq("foo")
          end

          expect(playbook.context).to eq("rspec")
        end
      end

      describe "#add_cli_options" do
        it "should delegate to inputs" do
          inputs.expects(:add_cli_options).with(app = stub, true)
          playbook.add_cli_options(app, true)
        end
      end

      describe "#inputs" do
        it "should delegate to inputs" do
          inputs.expects(:keys).returns(["rspec1", "rspec2"])
          expect(playbook.inputs).to eq(["rspec1", "rspec2"])
        end
      end

      describe "#input_value" do
        it "should delegate to inputs" do
          inputs.expects(:[]).with("rspec").returns("rspec value")
          expect(playbook.input_value("rspec")).to eq("rspec value")
        end
      end

      describe "#nodes" do
        it "should delegate to nodes" do
          nodes.expects(:keys).returns(["rspec1", "rspec2"])
          expect(playbook.nodes).to eq(["rspec1", "rspec2"])
        end
      end

      describe "#discovered_nodes" do
        it "should delegate to nodes" do
          nodes.expects(:[]).with("rspec").returns(["rspec"])
          expect(playbook.discovered_nodes("rspec")).to eq(["rspec"])
        end
      end

      describe "#metadata_item" do
        it "should get the right data" do
          playbook.from_hash(playbook_fixture)
          expect(playbook.metadata_item("name")).to eq("test_playbook")
        end

        it "should fail for unknown metadata" do
          expect { playbook.metadata_item("rspec") }.to raise_error("Unknown playbook metadata rspec")
        end
      end

      describe "#validate_agents" do
        it "should pass on the data to uses" do
          uses.expects(:validate_agents).with("rpcutil" => ["rspec1"])
          playbook.validate_agents("rpcutil" => ["rspec1"])
        end
      end

      describe "#prepare_tasks" do
        it "should prepare nodes with the right data" do
          playbook.from_hash(playbook_fixture)
          tasks.expects(:from_hash).with(playbook_fixture["tasks"])
          tasks.expects(:from_hash).with(playbook_fixture["hooks"])
          tasks.expects(:prepare)
          playbook.prepare_tasks
        end
      end

      describe "#prepare_nodes" do
        it "should prepare nodes with the right data" do
          playbook.from_hash(playbook_fixture)
          playbook.expects(:t).with(playbook_fixture["nodes"]).returns(playbook_fixture["nodes"])
          nodes.expects(:from_hash).with(playbook_fixture["nodes"]).returns(nodes)
          nodes.expects(:prepare)
          playbook.prepare_nodes
        end
      end

      describe "#prepare_uses" do
        it "should prepare uses with the right data" do
          playbook.from_hash(playbook_fixture)
          playbook.expects(:t).with(playbook_fixture["uses"]).returns(playbook_fixture["uses"])
          uses.expects(:from_hash).with(playbook_fixture["uses"]).returns(uses)
          uses.expects(:prepare)
          playbook.prepare_uses
        end
      end

      describe "#prepare_inputs" do
        it "should prepare inputs with the right data" do
          playbook.input_data = {"rspec" => true}
          inputs.expects(:prepare).with("rspec" => true)
          playbook.prepare_inputs
        end
      end

      describe "#loglevel" do
        it "should report the correct loglevel" do
          expect(playbook.loglevel).to eq("info")
          expect(Playbook.new("error").loglevel).to eq("error")
          playbook.from_hash(playbook_fixture)
          expect(playbook.loglevel).to eq("debug")
        end
      end

      describe "#version" do
        it "should report the correct version" do
          playbook.from_hash(playbook_fixture)
          expect(playbook.version).to eq("1.1.2")
        end
      end

      describe "#name" do
        it "should report the correct name" do
          playbook.from_hash(playbook_fixture)
          expect(playbook.name).to eq("test_playbook")
        end
      end

      describe "#run!" do
        it "should prepare and run the tasks" do
          seq = sequence(:run)
          playbook.expects(:validate_configuration!).in_sequence(seq)
          playbook.report.expects(:start!).returns(Time.now).in_sequence(seq)
          playbook.expects(:prepare).in_sequence(seq)
          tasks.expects(:run).in_sequence(seq).returns(true)
          playbook.expects(:release_playbook_locks).in_sequence(seq)
          playbook.report.expects(:finalize).with(true).returns({}).in_sequence(seq)

          expect(playbook.run!({})).to eq({})
        end
      end

      describe "#prepare" do
        it "should prepare in the right order" do
          seq = sequence(:prep)
          playbook.expects(:prepare_inputs).in_sequence(seq)
          playbook.expects(:prepare_data_stores).in_sequence(seq)
          playbook.expects(:obtain_playbook_locks).in_sequence(seq)
          playbook.expects(:prepare_uses).in_sequence(seq)
          playbook.expects(:prepare_nodes).in_sequence(seq)
          playbook.expects(:prepare_tasks).in_sequence(seq)
          playbook.prepare
        end
      end

      describe "#from_hash" do
        it "should load the metadata, setup logger and load the inputs" do
          playbook.expects(:set_logger_level)
          inputs.expects(:from_hash).with(playbook_fixture["inputs"])

          playbook.from_hash(playbook_fixture)

          expect(playbook.metadata).to eq(
            "name" => "test_playbook",
            "version" => "1.1.2",
            "author" => "R.I.Pienaar <rip@devco.net>",
            "description" => "test description",
            "tags" => ["test"],
            "on_fail" => "fail",
            "loglevel" => "debug",
            "run_as" => "choria=deployer.bob"
          )
        end
      end
    end
  end
end
