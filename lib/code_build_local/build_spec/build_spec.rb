require 'kwalify'

module CodeBuildLocal
  module BuildSpec

    # Phases of a buildspec file.

    PHASES = ['install', 'pre_build', 'build', 'post_build']

    # Error for communicating issues with buildspec

    class BuildSpecError < StandardError

      # @!attribute [r] filename
      #   @return [String] the filename of the buildspec that caused the error

      attr_accessor :filename

      def initialize(message, filename)
        @filename = filename
        super(message)
      end
    end
    
    # Class for representing a buildspec defined by a buildspec file.
    # @see http://docs.aws.amazon.com/codebuild/latest/userguide/build-spec-ref.html

    class BuildSpec

      # @!attribute [r] env
      #   @return [Map<String, String>] A mapping of environment variable names to values.
      # @!attribute [r] phases
      #   @return [Map<String, Array<String>>] A mapping of phase name to a list of commands
      #   for that phase

      attr_accessor :env, :phases

      # Parse a buildspec file to create a BuildSpec object. Parses the file according to a
      # buildspec schema.

      def initialize filename
        parse_file filename
      end

      private

      def parse_file filename
        schema_filename = File.join(File.dirname(__FILE__), './buildspec_schema.yml')
        schema = Kwalify::Yaml.load_file(schema_filename)
        validator = Kwalify::Validator.new(schema)
        parser = Kwalify::Yaml::Parser.new(validator)

        document = parser.parse_file(filename)

        version = document['version']
        if version != 0.2
          raise BuildSpecError.new("Unsupported version: #{version}. This only supports 0.2", filename)
        end

        errors = parser.errors
        if errors && !errors.empty?
          raise BuildSpecError.new("Encountered errors while validating buildspec: #{errors}", filename)
        end

        # parse env
        @env = document['env']['variables'] if document['env'] and document['env']['variables']
        @env ||= {}
        @env.freeze

        # parse phases
        @phases = {}
        for phase in PHASES
          @phases[phase] = document['phases'][phase]['commands'] unless document['phases'][phase].nil?
          @phases[phase] ||= []
        end
        @phases.freeze
      end
    end
  end
end
