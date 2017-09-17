require 'aws-sdk-core'
require 'colorize'
require 'docker'
require 'shellwords'

module CodeBuildLocal

  # Module for running CodeBuild projects on a local docker container.
  #
  # It is expected that you have a {CodeBuildLocal::SourceProvider} object that can yield a
  # path containing a project suitable for AWS Codebuild. The project should have a buildspec
  # file in its root directory. This module lets you use the default Ruby CodeBuild image or
  # specify your own. See {Runner#run} and {Runner#run_default}.
  #
  # @see Runner#run_default run_default - an easy to use method for running CodeBuild projects on the
  #   default Ruby 2.3.1 image
  # @see Runner#run run - a more configurable way of running CodeBuild projects locally

  class Runner

    # @!attribute [r] outstream
    #   @return [StringIO, nil] the output stream for the redirected stdout of the CodeBuild project, or nil if none was specified.
    # @!attribute [r] errstream
    #   @return [StringIO, nil] the output stream for the redirected stderr of the CodeBuild project, or nil if none was specified.
    attr_accessor :outstream, :errstream

    # Create a Runner instance.
    #
    # @param opts [Hash] A hash containing several optional values,
    #   for redirecting output.
    #   * *:outstream* (StringIO) --- for redirecting the codebuild project's stdout output
    #   * *:errstream* (StringIO) --- for redirecting the codebuild project's stderr output

    def initialize(opts)
      @outstream = opts[:outstream]
      @errstream = opts[:errstream]
    end

    # Run the CodeBuild project at the specified directory on the default AWS CodeBuild Ruby 2.3.1 image.
    #
    # @param path [String] The path to the CodeBuild project.
    # @return [Integer] The exit code from running the CodeBuild project.
    #
    # @see run
    # @see CodeBuildLocal::DefaultImages.build_aws_codebuild_image

    def run_default(path)
      run(
        CodeBuildLocal::DefaultImages.build_code_build_image,
        CodeBuildLocal::SourceProvider::FolderSourceProvider.new(path),
      )
    end

    # Run a CodeBuild project on the specified image.
    #
    # Run a CodeBuild project on the specified image, with the source pointed to by
    # the specified source provider. If the buildspec filename is not buildspec.yml or
    # is not located in the project root, specify an different relative path and file
    # for the parameter build_spec_name.
    #
    # @param image [Docker::Image] A docker image to run the CodeBuild project on.
    # @param source_provider [CodeBuildLocal::SourceProvider] A source provider that yields
    #   the source for the CodeBuild project.
    # @param build_spec_name [String] The relative path and filename for the buildspec file,
    #   relative to the root of the project.
    #
    # @return [Integer] The exit code from running the CodeBuild project.
    def run(image, source_provider, build_spec_name="buildspec.yml")
      Runner.configure_docker
      build_spec = Runner.make_build_spec(source_provider, build_spec_name)
      env = Runner.make_env(build_spec, Runner.get_credentials)
      container = Runner.make_container(image, source_provider, env)

      begin
        run_commands_on_container(container, build_spec)
      ensure
        unless container.nil?
          container.stop
          container.remove
        end
      end
    end
    
    private

    DEFAULT_TIMEOUT_SECONDS = 2000
    REMOTE_SOURCE_VOLUME_PATH_RO="/usr/app_ro/"
    REMOTE_SOURCE_VOLUME_PATH="/usr/app/"

    # Get credentials from AWS STS.
    # @see http://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/STS/Client.html AWS STS Client
    # @return [Hash] A hash containing session credentials for the globally configured AWS user,
    #   see {make_env} for expected credential symbols.

    def self.get_credentials
      Aws::STS::Client.new.get_session_token.credentials
    end

    # Make an array that contains environment variables according to the provided
    # build_spec and credentials.
    #
    # @param build_spec [CodeBuildLocal::BuildSpec::BuildSpec]
    # @param credentials [Hash] A hash containing AWS credential information.
    #   :access_key_id should contain the AWS access key id.
    #   :secret_access_key should contain the AWS secret access key.
    #   :session_token should contain the AWS session token, if applicable.
    #
    # @return [Array<String>] An array of env variables in the format KEY=FOO, KEY2=BAR

    def self.make_env(build_spec, credentials)
      env = []

      # load credentials, if they are specified
      unless credentials[:access_key_id].nil?
        env << "AWS_ACCESS_KEY_ID=#{credentials[:access_key_id]}"
      end
      unless credentials[:secret_access_key].nil?
        env << "AWS_SECRET_ACCESS_KEY=#{credentials[:secret_access_key]}"
      end
      unless credentials[:session_token].nil?
        env << "AWS_SESSION_TOKEN=#{credentials[:session_token]}"
      end

      build_spec.env.keys.each { |k| env << "#{k}=#{build_spec.env[k]}" }

      env
    end

    # Configure docker with some useful defaults.
    # 
    # Currently this just includes setting the docker read timeout to {DEFAULT_TIMEOUT_SECONDS} if
    # there is no read timeout already specified. Override this by setting Docker.options[:read_timeout]
    # to another value.
    # @return [void]

    def self.configure_docker
      Docker.options[:read_timeout] = DEFAULT_TIMEOUT_SECONDS if Docker.options[:read_timeout].nil?
    end

    # Construct a buildspec from the given project provided by the source provider.
    #
    # The buildspec file should be located at the root of the source directory
    # and named "buildspec.yml". An alternate path / filename can be specified by providing build_spec_name.
    #
    # @param source_provider [CodeBuildLocal::SourceProvider] A source provider that yields the path for
    #   the desired CodeBuild project.
    # @param build_spec_name [String] The path and file name for the buildspec file in the project directory.
    #
    # @return [CodeBuildLocal::BuildSpec::BuildSpec] A BuildSpec object representing the information contained
    #   by the specified buildspec.
    #
    # @see CodeBuildLocal::BuildSpec::BuildSpec

    def self.make_build_spec(source_provider, build_spec_name="buildspec.yml")
      CodeBuildLocal::BuildSpec::BuildSpec.new(File.join(source_provider.path, build_spec_name))
    end

    # Make a docker container from the specified image for running the CodeBuild project.
    #
    # The container:
    # * is created from the specified image.
    # * is setup with the specified environment variables.
    # * has a default command of "/bin/bash" with a tty configured, so that the image stays running when started.
    # * has the CodeBuild project source provided by the source_provider mounted to a readonly directory
    #   at {REMOTE_SOURCE_VOLUME_PATH_RO}.
    #
    # @param image [Docker::Image] The docker image to be used to create the CodeBuild project.
    # @param source_provider [CodeBuildLocal::SourceProvider] A source provider to provide the location
    #   of the project that will be mounted readonly to the image at the directory {REMOTE_SOURCE_VOLUME_PATH_RO}.
    # @param env [Hash] the environment to pass along to the container. Should be an array with elements of the
    #   format KEY=VAL, FOO=BAR, etc. See the output of {#make_env}.
    # @return [Docker::Container] a docker container from the specified image, with the specified settings applied.
    #   See method description.

    def self.make_container(image, source_provider, env)
      host_source_volume_path = source_provider.path
      Docker::Container.create(
        'Image' => image.id,
        'Env' => env,
        'Cmd' => '/bin/bash',
        'Tty' => true,
        'Volume' => {REMOTE_SOURCE_VOLUME_PATH_RO => {}}, 'Binds' => ["#{host_source_volume_path}:#{REMOTE_SOURCE_VOLUME_PATH_RO}:ro"],
      )
    end

    # Bookkeeping bash variable for tracking whether a command has exited unsuccessfully
    DO_NEXT = "_cbl_do_next_cmd_"
    # Bookkeeping bash variable for tracking the build phase exit code
    BUILD_EXIT_CODE = "_cbl_build_exit_code_"
    # Bookkeeping bash variable for tracking most phases' exit codes
    EXIT_CODE = "_cbl_exit_code_"
    # Prepend this to container debug messages
    DEBUG_HEADER = "[CodeBuildLocal Runner]"

    # Make a conditional shell command
    #
    # @param test [String] The variable to test.
    # @param zero [String] If test equals zero, run this command
    # @param not_zero [String] If test does not equal zero, run this command

    def make_if test, zero, not_zero
      noop = "echo -n"
      "if [ \"0\" -eq \"$#{test}\" ]; then #{zero || noop}; else #{not_zero || noop} ; fi"
    end

    # Make a shell command that will run if DO_NEXT is 0 (i.e. no errors)

    def maybe_command command
      make_if DO_NEXT, command, nil
    end

    # Make a shell command to print a debug message to stderr

    def debug_message message
      ">&2 echo #{DEBUG_HEADER} #{message}"
    end

    # Make a shell script to imitate the behavior of the CodeBuild agent.
    #
    # This duplicates the running semantics of CodeBuild, including phase order, shell session, behavior, etc.
    #
    # @param build_spec [CodeBuildLocal::BuildSpec::BuildSpec] A build spec object containing the commands to run
    # @return [Array<String>] An array to execute an agent script that runs the CodeBuild project
    
    def make_agent_script build_spec
      # Setup the container. Copy project to a writable dir, go to the dir, set bookkeeping vars
      commands = [
        "cp -r #{REMOTE_SOURCE_VOLUME_PATH_RO} #{REMOTE_SOURCE_VOLUME_PATH}",
        "cd #{REMOTE_SOURCE_VOLUME_PATH}",
        "#{DO_NEXT}=\"0\"",
        "#{EXIT_CODE}=\"0\"",
        "#{BUILD_EXIT_CODE}=\"0\"",
      ]

      CodeBuildLocal::BuildSpec::PHASES.each do |phase|
        commands << debug_message("Running phase \\\"#{phase}\\\"")

        build_spec.phases[phase].each do |cmd|
          # Run the given command, continue if the command exits successfully
          commands << debug_message("Running command \\\"#{cmd.shellescape}\\\"")
          commands << maybe_command("#{cmd} ; #{EXIT_CODE}=\"$?\"")
          commands << maybe_command(
            make_if(EXIT_CODE, nil, [
              "#{DO_NEXT}=\"$#{EXIT_CODE}\"",
              debug_message("Command failed \\\"#{cmd.shellescape}\\\""),
            ].join("\n"))
          )
        end

        commands << make_if(
          EXIT_CODE,
          debug_message("Completed phase \\\"#{phase}\\\", successful: true"),
          debug_message("Completed phase \\\"#{phase}\\\", successful: false"),
        )

        if phase == "build"
          # If the build phase exits successfully, dont exit, continue onto post_build
          commands << make_if(EXIT_CODE, nil, "#{BUILD_EXIT_CODE}=$#{EXIT_CODE};#{EXIT_CODE}=\"0\";#{DO_NEXT}=\"0\"")
        elsif phase == "post_build"
          # exit BUILD_EXIT_CODE || EXIT_CODE
          commands << make_if(BUILD_EXIT_CODE, nil, "exit $#{BUILD_EXIT_CODE}")
          commands << make_if(EXIT_CODE, nil, "exit $#{EXIT_CODE}")
        else
          commands << make_if(EXIT_CODE, nil, "exit $#{EXIT_CODE}")
        end
      end

      ["bash", "-c", commands.join("\n")]
    end

    # Run the commands of the given buildspec on the given container.
    #
    # Runs the phases in the order specified by the CodeBuild documentation.
    #
    # @see http://docs.aws.amazon.com/codebuild/latest/userguide/view-build-details.html#view-build-details-phases

    def run_commands_on_container(container, build_spec)
      agent_script = make_agent_script build_spec
      returned = container.tap(&:start).exec(agent_script, :wait => DEFAULT_TIMEOUT_SECONDS) do |stream, chunk|
        if stream == :stdout
          (@outstream || $stdout).print chunk
        else
          (@errstream || $stderr).print chunk
        end
      end
      returned[2]
    end
  end
end

