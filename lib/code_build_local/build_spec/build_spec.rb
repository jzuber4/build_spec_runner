require 'kwalify'
require 'yaml'

module CodeBuildLocal
  module BuildSpec

    # Phases of a buildspec file.

    PHASES = ['install', 'pre_build', 'build', 'post_build']

    # Error for communicating issues with buildspec

    class BuildSpecError < StandardError

      # @!attribute [r] filename
      #   @return [String] the filename of the buildspec that caused the error

      attr_reader :filename

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
      # @!attribute [r] paremeter_store
      #   @return [Map<String, String>] A mapping of parameter store environment variable names to the parameter store key.
      # @!attribute [r] phases
      #   @return [Map<String, Array<String>>] A mapping of phase name to a list of commands
      #   for that phase

      attr_reader :env, :parameter_store, :phases

      # Parse a buildspec file to create a BuildSpec object. Parses the file according to a
      # buildspec schema.

      def initialize filename
        @filename = filename
        parse_file
      end

      private

      # The filename of the build spec file, used for raising {BuildSpecError}s

      attr_reader :filename

      # Parse a buildspec yaml file to create a BuildSpec object. Uses a Kwalify schema for validation

      def parse_file
        document = YAML.load_file @filename
        validate_with_schema document

        validate_version document
        @env, @parameter_store = validate_env document 
        @phases          = validate_phases document
        validate_artifacts document
      end

      # Validate the buildspec file using a Kwalify schema
      #
      # @param document [Hash] a document object representing the build spec
      # @raise [BuildSpecError] if the build spec doesn't comply with the schema

      def validate_with_schema document
        schema_filename = File.join(File.dirname(__FILE__), './buildspec_schema.yml')
        schema = Kwalify::Yaml.load_file(schema_filename)

        errors = Kwalify::Validator.new(schema).validate document
        if errors && !errors.empty?
          raise BuildSpecError.new "Encountered errors while validating buildspec according to schema: #{errors}", @filename
        end
      end

      # Validate the build spec document's version
      #
      # @raise [BuildSpecError] if the version is not supported

      def validate_version document
        version = document['version']
        if version != 0.2
          raise BuildSpecError.new "Unsupported version: #{version}. This only supports 0.2", @filename
        end
      end

      # Validate and parse the build spec document's environment variables and parameter-store variables
      #
      # @raise [BuildSpecError] if the env variables or paremeter-store variables are invalid
      # @return [Array<String>, Array<String>] the environment variables and parameter store variables, in that order

      def validate_env document
        assert_not_nil_key document, 'env', 'Mapping "env" requires at least one of ["variables", "parameter-store"]'

        assert_not_nil_key document['env'], 'variables', 'Mapping "env => variables" requires at least one entry, if it exists'
        env = document['env']['variables'] if document['env'] and document['env']['variables']
        env ||= {}
        env.freeze

        assert_not_nil_key document['env'], 'parameter-store', 'Mapping "env => parameter-store" requires at least one entry, if it exists'
        parameter_store = document['env']['parameter-store'] if document['env'] and document['env']['parameter-store']
        parameter_store ||= {}
        parameter_store.freeze

        return env, parameter_store
      end

      # Validate and parse the build spec document's phases
      #
      # @raise [BuildSpecError] if the phase mappings are  invalid
      # @return [Hash<String, Array[String]>] a mapping of phase name to a list of commands in that phase

      def validate_phases document
        phases = {}
        for phase in PHASES
          assert_not_nil_key document['phases'], phase, "Mapping \"phases => #{phase}\" requires mapping \"commands\""
          phases[phase] = document['phases'][phase]['commands'] unless document['phases'][phase].nil?
          phases[phase] ||= []
        end
        phases
      end

      # Validate the build spec document's artifacts
      #
      # @raise [BuildSpecError] if the artifact mapping is invalid

      def validate_artifacts document
        assert_not_nil_key document, 'artifacts', 'Mapping "artifacts" requires mapping "files"'
      end

      # Assert that the document does not have the key with a nil value
      #
      # @raise [BuildSpecError] If the document has the key but the key's value is nil

      def assert_not_nil_key document, key, message
        if !document.nil? and document.key? key and document[key].nil?
          raise BuildSpecError.new message, @filename
        end
      end
    end
  end
end
