require 'docker'
require 'optparse'

module CodeBuildLocal
  class CLI

    # Run the CLI object, according to the parsed options.
    #
    # @see CLI.optparse

    def run
      path                = @options[:path]
      quiet               = @options[:quiet] || false
      build_spec_path     = @options[:build_spec_path]
      image_id            = @options[:image_id]
      aws_dockerfile_path = @options[:aws_dockerfile_path]

      # validate
      raise OptionParser::MissingArgument, 'Must specify a path (-p, --path PATH)' if path.nil?
      if image_id && aws_dockerfile_path
        raise OptionParser::InvalidOption, 'Cannot specify both --aws_dockerfile_path and --image_id,'\
          ' you must choose one image.'
      end

      # build
      image = if image_id
                Docker::Image.get(image_id)
              else
                CodeBuildLocal::DefaultImages.build_code_build_image :aws_dockerfile_path => aws_dockerfile_path
              end
      source_provider = CodeBuildLocal::SourceProvider::FolderSourceProvider.new path
      runner = make_runner :quiet => quiet

      # run
      runner.run image, source_provider, :build_spec_path => build_spec_path 
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

    # Create an optparse for parsing CLI options
    # 
    # The options are as follows:
    # * \-h \-\-help --- Output help message
    # * \-p \-\-path PATH --- Required argument, path the to the CodeBuild project to run
    # * \-q \-\-quiet --- Silence debug messages.
    # * \-\-build_spec_path BUILD_SPEC_PATH --- Alternative path for buildspec file, defaults to {Runner::DEFAULT_BUILD_SPEC_PATH}.
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
        opts.on('-p', '--path PATH',
                '[REQUIRED] Path to the CodeBuild project to run.') do |project_path|
          options[:path] = project_path
        end
        opts.on('-q', '--quiet',
                'Silence debug messages.') do
          options[:quiet] = true
        end
        opts.on('--build_spec_path BUILD_SPEC_PATH',
                'Alternative path for buildspec file, defaults to #{Runner::DEFAULT_BUILD_SPEC_PATH}.') do |build_spec_path|
          options[:build_spec_path] = build_spec_path
        end
        opts.on('--image_id IMAGE_ID',
                'Id of alternative docker image to use. NOTE: this cannot be specified at the same time as --aws_dockerfile_path') do |image_id|
          options[:image_id] = image_id
        end
        opts.on('--aws_dockerfile_path AWS_DOCKERFILE_PATH',
                'Alternative AWS CodeBuild DockerFile path, default is "ubuntu/ruby/2.3.1/". '\
                'NOTE: this cannot be specified at the same time as --image_id . '\
                'See: https://github.com/aws/aws-codebuild-docker-images') do |aws_dockerfile_path|
          options[:aws_dockerfile_path] = aws_dockerfile_path
        end
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

    attr_reader :options

    # Extension point for mocking interaction with runner

    def make_runner opts={}
      CodeBuildLocal::Runner.new opts
    end

  end
end

