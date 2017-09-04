require 'git'
require 'docker'

module CodeBuildLocal
  module DefaultImages
    REPO_NAME = 'aws-codebuild-docker-images'
    GIT_LOCATION = "https://github.com/aws/#{REPO_NAME}"
    REPO_PATH = '/tmp/code_build_local/'
    DEFAULT_DOCKERFILE_PATH = 'ubuntu/ruby/2.3.1/'

    ##
    # Pull down a repo that contains the aws codebuild docker images
    #
    def self.pull_aws_codebuild_images_repo opts
      repo_path = opts[:repo_path]
      repo_path ||= REPO_PATH
      begin
        r = Git.open("#{repo_path}/#{REPO_NAME}")
        if opts[:refresh]
          r.pull
        end
        r
      rescue ArgumentError
        Git.clone(GIT_LOCATION, REPO_NAME, :path => repo_path)
      end
    end

    ##
    # Build the default AWS codebuild image
    #
    def self.build_aws_codebuild_image(opts={})
      dockerfile_path = opts[:dockerfile_path]
      dockerfile_path ||= DEFAULT_DOCKERFILE_PATH
      repo = self.pull_aws_codebuild_images_repo opts
      docker_dir = "#{repo.dir.path}/#{dockerfile_path}"
      Docker::Image.build_from_dir(docker_dir)
    end
  end
end

