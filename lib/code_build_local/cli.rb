require 'docker'
require 'optparse'

module CodeBuildLocal
  class CLI

    # Run the CLI object, according to the parsed options.
    #
    # @see CLI.optparse

    def run
      source_provider = get_source_provider
      image           = get_image
      @options[:sts_client], @options[:no_creds] = get_client_or_no_creds

      CodeBuildLocal::Runner.run image, source_provider, @options
    end

    # Create a CLI object, parsing the specified argv, or ARGV if none specified.
    # 
    # @param argv [Array] array of arguments, defaults to ARGV
    # @return [CLI] a CLI object for running the CodeBuild project in a manner determined by argv. 
    # @see CLI.optparse

    def initialize argv = ARGV
      @options = {}
      CLI::optparse(@options).parse argv
    end

    # Create an OptParse for parsing CLI options
    #
    # The options are as follows:
    # * \-h \-\-help --- Output help message
    # * \-p \-\-path PATH --- Required argument, path the to the CodeBuild project to run
    # * \-q \-\-quiet --- Silence debug messages.
    # * \-\-build_spec_path BUILD_SPEC_PATH --- Alternative path for buildspec file, defaults to {Runner::DEFAULT_BUILD_SPEC_PATH}.
    # * \-\-profile --- AWS profile of the credentials to provide the container, defaults to the default profile.
    #   This cannot be specified at the same time as \-\-no_creds.
    # * \-\-no_creds --- Don't add AWS credentials to the CodeBuild project's container.
    #   This cannot be specified at the same time as \-\-profile.
    # * \-\-image_id IMAGE_ID --- Id of alternative docker image to use. This cannot be specified at the same time as \-\-aws_dockerfile_path
    # * \-\-aws_dockerfile_path AWS_DOCKERFILE_PATH --- Alternative AWS CodeBuild Dockerfile path, defaults to {DefaultImages::DEFAULT_DOCKERFILE_PATH}.
    #   This cannot be specified at the same time as \-\-image_id.
    #   See the {https://github.com/aws/aws-codebuild-docker-images AWS CodeBuild Docker Images repo} for the dockerfiles available through this option.
    #
    # @param options [Hash] the option hash to populate
    # @return [OptionParser] the option parser that parses the described options.

    def self.optparse options
      OptionParser.new do |opts|
        opts.banner = banner
        self.add_opt_path                opts, options
        self.add_opt_build_spec_path     opts, options
        self.add_opt_quiet               opts, options
        self.add_opt_image_id            opts, options
        self.add_opt_aws_dockerfile_path opts, options
        self.add_opt_profile             opts, options
        self.add_opt_no_creds            opts, options
      end
    end

    # Banner for the CLI usage.

    def self.banner
      %|Usage: #{File.basename(__FILE__)} arguments

Run a CodeBuild project locally.

Arguments:
      |
    end

    # Create and execute a CLI with the default ARGV

    def self.main
      CLI::new.run
    end

    private

    # Contains the options parsed from the OptParse

    attr_reader :options

    ##### Adding Options #####

    def self.add_opt_path opts, options
      opts.on('-p', '--path PATH',
              '[REQUIRED] Path to the CodeBuild project to run.') do |project_path|
        options[:path] = project_path
      end
    end

    def self.add_opt_build_spec_path opts, options
      opts.on('--build_spec_path BUILD_SPEC_PATH',
              'Alternative path for buildspec file, defaults to #{Runner::DEFAULT_BUILD_SPEC_PATH}.') do |build_spec_path|
        options[:build_spec_path] = build_spec_path
      end
    end

    def self.add_opt_quiet opts, options
      opts.on('-q', '--quiet',
              'Silence debug messages.') do
        options[:quiet] = true
      end
    end

    def self.add_opt_image_id opts, options
      opts.on('--image_id IMAGE_ID',
              'Id of alternative docker image to use. NOTE: this cannot be specified at the same time as --aws_dockerfile_path') do |image_id|
        options[:image_id] = image_id
      end
    end

    def self.add_opt_aws_dockerfile_path opts, options
      opts.on('--aws_dockerfile_path AWS_DOCKERFILE_PATH',
              'Alternative AWS CodeBuild DockerFile path, default is "ubuntu/ruby/2.3.1/". '\
              'NOTE: this cannot be specified at the same time as --image_id . '\
              'See: https://github.com/aws/aws-codebuild-docker-images') do |aws_dockerfile_path|
        options[:aws_dockerfile_path] = aws_dockerfile_path
      end
    end

    def self.add_opt_profile opts, options
      opts.on('--profile PROFILE',
              'AWS profile of the credentials to provide the container, defaults to the default profile. '\
              'This cannot be set at the same time as --no_creds.') do |profile|
        options[:profile] = profile
      end
    end

    def self.add_opt_no_creds opts, options
      opts.on('--no_creds',
              'Don\'t add AWS credentials to the CodeBuild project\'s container. '\
              'This cannot be set at the same time as --profile.') do
        options[:no_creds] = true
      end
    end

    ##### Parsing #####

    # Create a source provider from the path option.
    # The path option must be specified.

    def get_source_provider
      path = @options.delete :path
      raise OptionParser::MissingArgument, 'Must specify a path (-p, --path PATH)' if path.nil?
      CodeBuildLocal::SourceProvider::FolderSourceProvider.new path
    end

    # Choose the image based on the aws_dockerfile_path and image_id options.
    # Up to one can be specified.

    def get_image
      image_id, aws_dockerfile_path = CLI::only_one @options, :image_id, :aws_dockerfile_path
      if image_id
        Docker::Image.get(image_id)
      elsif aws_dockerfile_path
        CodeBuildLocal::DefaultImages.build_code_build_image :aws_dockerfile_path => aws_dockerfile_path
      else
        CodeBuildLocal::DefaultImages.build_code_build_image
      end
    end

    # Choose whether to create an sts_client or specify no credentials based on the profile and no_creds options.
    # Up to one can be specified.

    def get_client_or_no_creds
      profile, no_creds = CLI::only_one @options, :profile, :no_creds
      sts_client = Aws::STS::Client.new profile: profile if profile
      return sts_client, no_creds
    end

    # Remove and return one of the two keys from the document, if either exists.
    # If both exist, raise an error.
    #
    # @raise [OptionParser::InvalidOption] if both keys exist
    # @return a pair (value1, value2) where up to one of entry has the value of the corresponding key in the document

    def self.only_one document, key1, key2
      value1, value2 = document.delete(key1), document.delete(key2)
      if value1 and value2
        raise OptionParser::InvalidOption, "Cannot specify both #{key1} and #{key2}"
      end
      return value1, value2
    end
  end
end
