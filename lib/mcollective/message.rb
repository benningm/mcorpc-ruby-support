module MCollective
  # container for a message, its headers, agent, collective and other meta data
  class Message
    attr_reader :message, :request, :validated, :msgtime, :payload, :type, :expected_msgid, :reply_to
    attr_accessor :headers, :agent, :collective, :filter, :requestid, :discovered_hosts, :options, :ttl

    VALIDTYPES = [:message, :request, :direct_request, :reply].freeze

    # payload                  - the message body without headers etc, just the text
    # message                  - the original message received from the middleware
    # options[:base64]         - if the body base64 encoded?
    # options[:agent]          - the agent the message is for/from
    # options[:collective]     - the collective its for/from
    # options[:headers]        - the message headers
    # options[:type]           - an indicator about the type of message, :message, :request, :direct_request or :reply
    # options[:request]        - if this is a reply this should old the message we are replying to
    # options[:filter]         - for requests, the filter to encode into the message
    # options[:options]        - the normal client options hash
    # options[:ttl]            - the maximum amount of seconds this message can be valid for
    # options[:expected_msgid] - in the case of replies this is the msgid it is expecting in the replies
    # options[:requestid]      - specific request id to use else one will be generated
    def initialize(payload, message, options={})
      options = {:base64 => false,
                 :agent => nil,
                 :headers => {},
                 :type => :message,
                 :request => nil,
                 :filter => Util.empty_filter,
                 :options => {},
                 :ttl => 60,
                 :expected_msgid => nil,
                 :requestid => nil,
                 :collective => nil}.merge(options)

      @payload = payload
      @message = message
      @requestid = options[:requestid]
      @discovered_hosts = nil
      @reply_to = nil

      @type = options[:type]
      @headers = options[:headers]
      @base64 = options[:base64]
      @filter = options[:filter]
      @expected_msgid = options[:expected_msgid]
      @options = options[:options]

      @ttl = @options[:ttl] || Config.instance.ttl
      @msgtime = 0

      @validated = false

      if options[:request]
        @request = options[:request]
        @agent = request.agent
        @collective = request.collective
        @type = :reply
      else
        @agent = options[:agent]
        @collective = options[:collective]
      end

      base64_decode!
    end

    # Sets the message type to one of the known types.  In the case of :direct_request
    # the list of hosts to communicate with should have been set with #discovered_hosts
    # else an exception will be raised.  This is for extra security, we never accidentally
    # want to send a direct request without a list of hosts or something weird like that
    # as it might result in a filterless broadcast being sent.
    #
    # Additionally you simply cannot set :direct_request if direct_addressing was not enabled
    # this is to force a workflow that doesnt not yield in a mistake when someone might assume
    # direct_addressing is enabled when its not.
    def type=(type)
      raise "Unknown message type #{type}" unless VALIDTYPES.include?(type)

      if type == :direct_request
        raise "Direct requests is not enabled using the direct_addressing config option" unless Config.instance.direct_addressing

        raise "Can only set type to :direct_request if discovered_hosts have been set" unless @discovered_hosts && !@discovered_hosts.empty?

        # clear out the filter, custom discovery sources might interpret the filters
        # different than the remote mcollectived and in directed mode really the only
        # filter that matters is the agent filter
        @filter = Util.empty_filter
        @filter["agent"] << @agent
      end

      @type = type
    end

    # Sets a custom reply-to target for requests.  The connector plugin should inspect this
    # when constructing requests and set this header ensuring replies will go to the custom target
    # otherwise the connector should just do what it usually does
    def reply_to=(target)
      raise "Custom reply targets can only be set on requests" unless [:request, :direct_request].include?(@type)

      @reply_to = target
    end

    # in the case of reply messages we are expecting replies to a previously
    # created message.  This stores a hint to that previously sent message id
    # and can be used by other classes like the security plugins as a means
    # of optimizing their behavior like by ignoring messages not directed
    # at us.
    def expected_msgid=(msgid)
      raise "Can only store the expected msgid for reply messages" unless @type == :reply

      @expected_msgid = msgid
    end

    def base64_decode!
      return unless @base64

      @payload = SSL.base64_decode(@payload)
      @base64 = false
    end

    def base64_encode!
      return if @base64

      @payload = SSL.base64_encode(@payload)
      @base64 = true
    end

    def base64?
      @base64
    end

    def description
      cid = ""
      cid += "#{payload[:callerid]}@" if payload.include?(:callerid)
      cid += payload[:senderid]

      "#{requestid} for agent '#{agent}' in collective '#{collective}' from #{cid}"
    end

    def encode!
      case type
      when :reply
        raise "Cannot encode a reply message if no request has been associated with it" unless request

        unless PluginManager["security_plugin"].valid_callerid?(request.payload[:callerid])
          raise "callerid in original request is not valid, surpressing reply to potentially forged request"
        end

        @requestid = request.payload[:requestid]
        @payload = PluginManager["security_plugin"].encodereply(agent, payload, requestid, request.payload[:callerid])
      when :request, :direct_request
        @requestid ||= create_reqid
        @payload = PluginManager["security_plugin"].encoderequest(Config.instance.identity, payload, requestid, filter, agent, collective, ttl)
      else
        raise "Cannot encode #{type} messages"
      end
    end

    def decode!
      raise "Cannot decode message type #{type}" unless [:request, :reply].include?(type)

      begin
        @payload = PluginManager["security_plugin"].decodemsg(self)
      rescue Exception => e # rubocop:disable Lint/RescueException
        if type == :request
          # If we're a server receiving a request, reraise
          raise(e)
        else
          # We're in the client, log and carry on as best we can

          # NOTE: mc_sender is unverified.  The verified identity is in the
          # payload we just failed to decode
          Log.warn("Failed to decode a message from '#{headers['mc_sender']}': #{e}")
          return
        end
      end

      if type == :request && !PluginManager["security_plugin"].valid_callerid?(payload[:callerid])
        raise "callerid in request is not valid, surpressing reply to potentially forged request"
      end

      [:collective, :agent, :filter, :requestid, :ttl, :msgtime].each do |prop|
        instance_variable_set("@#{prop}", payload[prop]) if payload.include?(prop)
      end
    end

    # Perform validation against the message by checking filters and ttl
    def validate
      raise "Can only validate request messages" unless type == :request

      msg_age = Time.now.utc.to_i - msgtime

      raise(MsgTTLExpired, "Message #{description} created at #{msgtime} is #{msg_age} seconds old, TTL is #{ttl}. Rejecting message.") if msg_age > ttl
      raise(NotTargettedAtUs, "Message #{description} does not pass filters. Ignoring message.") unless PluginManager["security_plugin"].validate_filter?(payload[:filter])

      @validated = true
    end

    # publish a reply message by creating a target name and sending it
    def publish
      # If we've been specificaly told about hosts that were discovered
      # use that information to do P2P calls if appropriate else just
      # send it as is.
      config = Config.instance
      if @discovered_hosts && config.direct_addressing && (@discovered_hosts.size <= config.direct_addressing_threshold)
        self.type = :direct_request
        Log.debug("Handling #{requestid} as a direct request")
      end

      PluginManager["connector_plugin"].publish(self)
    end

    def create_reqid
      # we gsub out the -s so that the format of the id does not
      # change from previous versions, these should just be more
      # unique than previous ones
      SSL.uuid.gsub("-", "")
    end
  end
end
