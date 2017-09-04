require 'kwalify'

module CodeBuildLocal
  module BuildSpec
    ##
    # Error for communicating issues with buildspec
    #
    # has instance variable @filename, for the filename of the buildspec that caused the error
    #
    class BuildSpecError < StandardError
      def initialize(message, filename)
        @filename = filename
        super(message)
      end
    end
    
    ##
    # Class for storing information on a buildspec
    #
    # Parse a buildspec.yml file with BuildSpec.new('your_filename')
    # Retrieve the env with BuildSpec#env and the phases with Buildspec#phases
    class BuildSpec
      def env
        @env
      end

      def phases
        @phases
      end

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
        @env = document['env']['variables'] if document['env']
        @env ||= {}
        @env.freeze

        # parse phases
        @phases = {}
        for phase in ['install', 'pre_build', 'build', 'post_build']
          @phases[phase] = document['phases'][phase]['commands'] if document['phases'][phase]
          @phases[phase] ||= []
        end
        @phases.freeze
      end
    end
  end
end
