module MCollective
  module DDL
    # A DDL class specific to agent plugins.
    #
    # A full DDL can be seen below with all the possible bells and whistles present.
    #
    # metadata    :name        => "Utilities and Helpers for SimpleRPC Agents",
    #             :description => "General helpful actions that expose stats and internals to SimpleRPC clients",
    #             :author      => "R.I.Pienaar <rip@devco.net>",
    #             :license     => "Apache License, Version 2.0",
    #             :version     => "1.0",
    #             :url         => "https://docs.puppetlabs.com/mcollective/",
    #             :timeout     => 10
    #
    # action "get_fact", :description => "Retrieve a single fact from the fact store" do
    #      display :always
    #
    #      input :fact,
    #            :prompt      => "The name of the fact",
    #            :description => "The fact to retrieve",
    #            :type        => :string,
    #            :validation  => '^[\w\-\.]+$',
    #            :optional    => false,
    #            :maxlength   => 40,
    #            :default     => "fqdn"
    #
    #      output :fact,
    #             :description => "The name of the fact being returned",
    #             :display_as  => "Fact"
    #
    #      output :value,
    #             :description => "The value of the fact",
    #             :display_as  => "Value",
    #             :default     => ""
    #
    #     summarize do
    #         aggregate summary(:value)
    #     end
    # end
    class AgentDDL < Base
      def initialize(plugin, plugintype=:agent, loadddl=true)
        @process_aggregate_functions = nil

        super
      end

      def client_activated?
        Util.str_to_bool(@config.pluginconf.fetch("%s.activate_client" % @pluginname, ACTIVATION_DEFAULT.to_s))
      end

      def input(argument, properties)
        raise "Input needs a :optional property" unless properties.include?(:optional)

        super
      end

      # Calls the summarize block defined in the ddl. Block will not be called
      # if the ddl is getting processed on the server side. This means that
      # aggregate plugins only have to be present on the client side.
      #
      # The @process_aggregate_functions variable is used by the method_missing
      # block to determine if it should kick in, this way we very tightly control
      # where we activate the method_missing behavior turning it into a noop
      # otherwise to maximise the chance of providing good user feedback
      def summarize(&block)
        unless @config.mode == :server
          @process_aggregate_functions = true
          yield
          @process_aggregate_functions = nil
        end
      end

      # Sets the aggregate array for the given action
      def aggregate(function, format={:format => nil})
        raise(DDLValidationError, "Formats supplied to aggregation functions should be a hash") unless format.is_a?(Hash)
        raise(DDLValidationError, "Formats supplied to aggregation functions must have a :format key") unless format.keys.include?(:format)
        raise(DDLValidationError, "Functions supplied to aggregate should be a hash") unless function.is_a?(Hash)

        unless function.keys.include?(:args) && function[:args]
          raise DDLValidationError, "aggregate method for action '%s' missing a function parameter" % entities[@current_entity][:action]
        end

        entities[@current_entity][:aggregate] ||= []
        entities[@current_entity][:aggregate] << (format[:format].nil? ? function : function.merge(format))
      end

      # Sets the display preference to either :ok, :failed, :flatten or :always
      # operates on action level
      def display(pref)
        Log.warn("The display option :flatten is being deprecated and will be removed in the next minor release.") if pref == :flatten

        # defaults to old behavior, complain if its supplied and invalid
        raise "Display preference #{pref} is not valid, should be :ok, :failed, :flatten or :always" unless [:ok, :failed, :flatten, :always].include?(pref)

        action = @current_entity
        @entities[action][:display] = pref
      end

      # Creates the definition for an action, you can nest input definitions inside the
      # action to attach inputs and validation to the actions
      #
      #    action "status", :description => "Restarts a Service" do
      #       display :always
      #
      #       input  "service",
      #              :prompt      => "Service Action",
      #              :description => "The action to perform",
      #              :type        => :list,
      #              :optional    => true,
      #              :list        => ["start", "stop", "restart", "status"]
      #
      #       output "status",
      #              :description => "The status of the service after the action"
      #
      #    end
      def action(name, input, &block)
        raise "Action needs a :description property" unless input.include?(:description)

        unless @entities.include?(name)
          @entities[name] = {}
          @entities[name][:action] = name
          @entities[name][:input] = {}
          @entities[name][:output] = {}
          @entities[name][:display] = :failed
          @entities[name][:description] = input[:description]
        end

        # if a block is passed it might be creating input methods, call it
        # we set @current_entity so the input block can know what its talking
        # to, this is probably an epic hack, need to improve.
        @current_entity = name
        yield if block_given?
        @current_entity = nil
      end

      # If the method name matches a # aggregate function, we return the function
      # with args as a hash.  This will only be active if the @process_aggregate_functions
      # is set to true which only happens in the #summarize block
      def method_missing(name, *args, &block)
        super unless @process_aggregate_functions || is_function?(name)

        {:function => name, :args => args}
      end

      def respond_to_missing?(method, *)
        @process_aggregate_functions || is_function?(name) || super
      end

      # Checks if a method name matches a aggregate plugin.
      # This is used by method missing so that we dont greedily assume that
      # every method_missing call in an agent ddl has hit a aggregate function.
      def is_function?(method_name)
        PluginManager.find("aggregate").include?(method_name.to_s)
      end

      # For a given action and arguments look up the DDL interface to that action
      # and if any arguments in the DDL have a :default value assign that to any
      # input that does not have an argument in the input arguments
      #
      # This is intended to only be called on clients and not on servers as the
      # clients should never be able to publish non compliant requests and the
      # servers should really not tamper with incoming requests since doing so
      # might raise validation errors that were not raised on the client breaking
      # our fail-fast approach to input validation
      def set_default_input_arguments(action, arguments)
        input = action_interface(action)[:input]

        return unless input

        input.each_key do |key|
          if key.is_a?(Symbol) && arguments.include?(key.to_s) && !input.include?(key.to_s)
            compat_arg = key.to_s
          else
            compat_arg = key
          end

          if !arguments.include?(compat_arg) && !input[key][:default].nil? && !input[key][:optional]
            Log.debug("Setting default value for input '%s' to '%s'" % [key, input[key][:default]])
            arguments[compat_arg] = input[key][:default]
          end
        end
      end

      # Creates a new set of arguments with string arguments mapped to symbol ones
      #
      # This is to assist with moving to a JSON pure world where requests might come
      # in from REST or other languages, those languages and indeed JSON itself does
      # not support symbols.
      #
      # It ensures a backward compatible mode where for rpcutil both of these requests
      # are equivelant
      #
      #   c.get_fact(:fact => "cluster")
      #   c.get_fact("fact" => "cluster")
      #
      # The case where both :fact and "fact" is in the DDL cannot be handled correctly
      # and this code will assume the caller means "fact" in that case.  There's no
      # way to represent such a request in JSON and just in general sounds like a bad
      # idea, so a warning is logged which would in default client configuration appear
      # on the clients display
      def symbolize_basic_input_arguments(input, arguments)
        warned = false

        Hash[arguments.map do |key, value|
          if input.include?(key.intern) && input.include?(key.to_s) && !warned
            Log.warn("String and Symbol versions of input %s found in the DDL for %s, ensure your DDL keys are unique." % [key, @pluginname])
            warned = true
          end

          if key.is_a?(String) && input.include?(key.intern) && !input.include?(key)
            [key.intern, value]
          else
            [key, value]
          end
        end]
      end

      # Helper to use the DDL to figure out if the remote call to an
      # agent should be allowed based on action name and inputs.
      def validate_rpc_request(action, arguments)
        # is the action known?
        raise DDLValidationError, "Attempted to call action #{action} for #{@pluginname} but it's not declared in the DDL" unless actions.include?(action)

        input = action_interface(action)[:input] || {}
        compatible_args = symbolize_basic_input_arguments(input, arguments)

        input.each_key do |key|
          raise DDLValidationError, "Action #{action} needs a #{key} argument" if !input[key][:optional] && !compatible_args.include?(key)

          validate_input_argument(input, key, compatible_args[key]) if compatible_args.include?(key)
        end

        true
      end

      # Returns the interface for a specific action
      def action_interface(name)
        @entities[name] || {}
      end

      # Returns an array of actions this agent support
      def actions
        @entities.keys
      end
    end
  end
end
