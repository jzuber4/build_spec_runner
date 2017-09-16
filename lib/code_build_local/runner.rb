require 'aws-sdk-core'
require 'colorize'
require 'docker'
require 'securerandom'

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
    # @!attribute [r] dbgstream
    #   @return [StringIO, nil] the output stream for redirected debug messages, or nil if none was specified.
    attr_accessor :outstream, :errstream, :dbgstream

    # Create a Runner instance.
    #
    # @param opts [Hash] A hash containing several optional values,
    #   for redirecting output.
    #   * *:outstream* (StringIO) --- for redirecting the codebuild project's stdout output
    #   * *:errstream* (StringIO) --- for redirecting the codebuild project's stderr output
    #   * *:dbgstream* (StringIO) --- for redirecting the runner's debug output (which otherwise goes to stderr)

    def initialize(opts)
      @outstream = opts[:outstream]
      @errstream = opts[:errstream]
      @dbgstream = opts[:dbgstream]
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
        Runner.prep_container container
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
        # Create an image with env that includes AWS credentials and buildspec env vars
        'Env' => env, 'Image' => image.id,
        # Set default command to a shell so that the container stays running
        'Cmd' => "/bin/bash", 'Tty' => true,
        # Mount project source as readonly
        'Volume' => {REMOTE_SOURCE_VOLUME_PATH_RO => {}}, 'Binds' => ["#{host_source_volume_path}:#{REMOTE_SOURCE_VOLUME_PATH_RO}:ro"]
      ) 
    end

    # Prepare the container to run commands.
    # * The container is started.
    # * The readonly source directory is copied from {REMOTE_SOURCE_VOLUME_PATH_RO}
    #   to a writable directory at {REMOTE_SOURCE_VOLUME_PATH}, for projects that require
    #   write permissions on the project directory.

    def self.prep_container container
      container.tap(&:start)
      container.exec(['cp', '-r', REMOTE_SOURCE_VOLUME_PATH_RO, REMOTE_SOURCE_VOLUME_PATH])
    end

    # Craft a command that can be sent to the running docker container to execute a single
    # project command.
    #
    # Each command needs to be wrapped with code to move to the correct directory
    # This is certainly hacky, but I didn't find a nicer way yet to have granular
    # command-by-command control of buildspec file execution.
    #
    # @param command [String] the command to be run
    # @return [Array<String>] an array describing the (bash) command to be run on the container.

    def self.make_command command
      shell_command = ""
      shell_command << "cd #{REMOTE_SOURCE_VOLUME_PATH}\n"
      shell_command << "#{command}\n"
      ["bash", "-c", shell_command]
    end

    # Run all the commands in a given phase.
    #
    # Runs all the commands in a given phase, until any of them exit unsuccessfully. Has nice
    # printing for stdout versus stderr, as well as debug commands that describe which phase
    # and commands are being run.
    #
    # @param container [Docker::Container] The docker container to run the commands on, expects
    #   settings configured by {make_container} and {prep_container}.
    # @param phases [Hash] A hash containing phases.
    # @param phase_name [String] The name of the current phase
    #
    # @return [Integer] The exit code.

    def run_phase(container, phases, phase_name)
      (@dbgstream || $stderr).puts "[CodeBuildLocal Runner] Running phase \"#{phase_name}\"".yellow
      phases[phase_name].each do |command|
        (@dbgstream || $stderr).puts "[CodeBuildLocal Runner] Running command \"#{command}\"".yellow
        returned = container.exec(Runner.make_command(command), :wait => DEFAULT_TIMEOUT_SECONDS) do |stream, chunk|
          if stream == :stderr
            (@errstream || $stderr).print chunk
          else
            (@outstream || $stdout).print chunk
          end
        end
        exit_code = returned[2]
        return exit_code if exit_code != 0
      end
      0
    end

    # Run the commands of the given buildspec on the given container.
    #
    # Runs the phases in the order specified by the CodeBuild documentation.
    #
    # @see http://docs.aws.amazon.com/codebuild/latest/userguide/view-build-details.html#view-build-details-phases

    def run_commands_on_container(container, build_spec)
      exit_code = run_phase(container, build_spec.phases, "install")
      return exit_code if exit_code != 0
      exit_code = run_phase(container, build_spec.phases, "pre_build")
      return exit_code if exit_code != 0

      build_exit_code = run_phase(container, build_spec.phases, "build")
      post_build_exit_code = run_phase(container, build_spec.phases, "post_build")
      if build_exit_code != 0
        build_exit_code
      else
        post_build_exit_code
      end
    end
  end
end

