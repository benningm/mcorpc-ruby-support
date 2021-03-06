module MCollective
  module Validator
    @last_load = nil
    @@validator_mutex = Mutex.new # rubocop:disable Style/ClassVars

    # Loads the validator plugins. Validators will only be loaded every 5 minutes
    def self.load_validators
      @@validator_mutex.lock
      if load_validators?
        @last_load = Time.now.to_i
        PluginManager.find_and_load("validator")
      end
    ensure
      @@validator_mutex.unlock
    end

    # Returns and instance of the Plugin class from which objects can be created.
    # Valid plugin names are
    #   :valplugin
    #   "valplugin"
    #   "ValpluginValidator"
    def self.[](klass)
      if klass.is_a?(Symbol)
        klass = validator_class(klass)
      elsif !klass.match(/.*Validator$/)
        klass = validator_class(klass)
      end

      const_get(klass)
    end

    # Allows validation plugins to be called like module methods : Validator.validate()
    def self.method_missing(method, *args, &block)
      if has_validator?(method)
        Validator[method].validate(*args)
      else
        raise ValidatorError, "Unknown validator: '#{method}'."
      end
    end

    def self.respond_to_missing?(method, *)
      has_validator?(method)
    end

    def self.has_validator?(validator)
      const_defined?(validator_class(validator))
    end

    def self.validator_class(validator)
      "#{validator.to_s.capitalize}Validator"
    end

    def self.load_validators?
      return true if @last_load.nil?

      (@last_load - Time.now.to_i) > 300
    end

    # Generic validate method that will call the correct validator
    # plugin based on the type of the validation parameter
    def self.validate(validator, validation)
      Validator.load_validators

      begin
        if [:integer, :boolean, :float, :number, :string, :array, :hash].include?(validation)
          Validator.typecheck(validator, validation)

        else
          case validation
          when Regexp, String
            Validator.regex(validator, validation)

          when Symbol
            Validator.send(validation, validator)

          when Array
            Validator.array(validator, validation)

          when Class
            Validator.typecheck(validator, validation)
          end
        end
      rescue => e
        raise ValidatorError, e.to_s, e.backtrace
      end
    end
  end
end
