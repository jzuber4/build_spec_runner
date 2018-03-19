require 'git'
require 'docker'

module BuildSpecRunner

  # Module for building the default AWS CodeBuild images. See {DefaultImages.build_image}

  module DefaultImages

    # The default directory used to clone the AWS CodeBuild Images repo
    REPO_PATH = '/tmp/build_spec_runner/'
    # The default CodeBuild Dockerfile
    DEFAULT_DOCKERFILE_PATH = 'ubuntu/ruby/2.3.1/'

    # Build an AWS CodeBuild Docker image.
    #
    # Defaults to the AWS CodeBuild Ruby 2.3.1 image.
    # Different AWS CodeBuild images can be specified by setting :aws_dockerfile_path
    # to a different setting, the default is {DEFAULT_DOCKERFILE_PATH}.
    # This method clones the {https://github.com/aws/aws-codebuild-docker-images AWS CodeBuild Images repo}
    # locally. The repo will be cloned to {REPO_PATH}, unless a different repo path is
    # specified by setting :repo_path.
    #
    # @param opts [Hash] A hash containing optional values
    #   * *:dockerfile_path* (String) --- override chosen AWS CodeBuild dockerfile. 
    #   * *:repo_path* (String) --- override path to clone AWS CodeBuild repo.
    #
    # @return [Docker::Image] A docker image with the specified AWS CodeBuild image.
    #
    # @see https://github.com/aws/aws-codebuild-docker-images AWS CodeBuild Images Repo

    def self.build_image opts={}

      dockerfile_path = opts[:aws_dockerfile_path]
      dockerfile_path ||= DEFAULT_DOCKERFILE_PATH
      repo_path = opts[:repo_path]
      repo_path ||= REPO_PATH

      repo = self.load_image_repo repo_path
      docker_dir = File.join(repo.dir.path, dockerfile_path)
      Docker::Image.build_from_dir(docker_dir)
    end

    private

    REPO_NAME = 'aws-codebuild-docker-images'
    GIT_LOCATION = File.join("https://github.com/aws/", REPO_NAME)

    # Load a repo that contains the aws codebuild docker images.
    #
    # Clone the repo if it hasn't yet been cloned, otherwise pull.
    #
    # @param repo_path [String] The path containing the repo.
    #
    # @return [Git::Base] A git repo
    #
    def self.load_image_repo repo_path
      begin
        # pull if it already exists
        r = Git.open(File.join(repo_path, REPO_NAME))
        r.pull
        r
      rescue ArgumentError # if it hasn't been cloned yet
        Git.clone(GIT_LOCATION, REPO_NAME, :path => repo_path)
      end
    end
  end
end

