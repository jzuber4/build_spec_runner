require 'docker'
require 'aws-sdk'
require 'securerandom'

module CodeBuildLocal
  module Runner

    ENV_FILE="/tmp/cbl_env"
    REMOTE_SOURCE_VOLUME_PATH_RO="/usr/app_ro/"
    REMOTE_SOURCE_VOLUME_PATH="/usr/app/"

    def self.get_credentials
      Aws::STS::Client.new.get_session_token.credentials
    end

    def self.make_env buildspec
      credentials = self.get_credentials
      env = [
        "AWS_ACCESS_KEY_ID=#{credentials[:access_key_id]}",
        "AWS_SECRET_ACCESS_KEY=#{credentials[:secret_access_key]}",
        "AWS_SESSION_TOKEN=#{credentials[:session_token]}",
      ]
      buildspec.env.keys.each { |k| env << "#{k}=#{buildspec.env[k]}" }

      env
    end

    def self.run_default(path)
      self.run(
        CodeBuildLocal::DefaultImages.build_aws_codebuild_image,
        CodeBuildLocal::BuildSpec::BuildSpec.new(File.join(path, "buildspec.yml")),
        CodeBuildLocal::SourceProvider::FolderSourceProvider.new(path),
      )
    end

    def self.run(image, buildspec, source_provider)
      env = make_env buildspec
      host_source_volume_path = source_provider.path
      container = Docker::Container.create(
        'Env' => env, 'Image' => image.id, 'Cmd' => "/bin/bash",
        'Tty' => true, 'Volume' => {REMOTE_SOURCE_VOLUME_PATH_RO => {}},
        'Binds' => ["#{host_source_volume_path}:#{REMOTE_SOURCE_VOLUME_PATH_RO}:ro"]) 
      container.tap(&:start)
        .exec(['touch', ENV_FILE])

      container.exec(['cp', '-r', REMOTE_SOURCE_VOLUME_PATH_RO, REMOTE_SOURCE_VOLUME_PATH])
      
      code = self.run_commands(container, "install", buildspec.phases["install"])
      if code != 0
        return code
      end
      code = self.run_commands(container, "pre_install", buildspec.phases["pre_build"])
      if code != 0
        return code
      end
      code = self.run_commands(container, "build", buildspec.phases["build"])
      code ||= self.run_commands(container, "post_build", buildspec.phases["post_build"])
      return code
    end

    def self.run_commands(container, step_name, cmds)
      cmds.each do |cmd|
        puts "cmd: #{cmd}"
        wait = 1000 
        res = container.exec(self.make_command(cmd), 'wait' => wait)
        self.print_out(res[0])
        if res[2] != 0
          puts "Step #{step_name} exited with code: #{res[2]}"
          return res[2]
        end
      end
      return 0
    end

    def self.make_command cmd
      ["bash", "-c", "cd #{REMOTE_SOURCE_VOLUME_PATH} && " +
       "set -o allexport && source /tmp/cbl_env && set +o allexport; #{cmd} ; " +
       "_CBL_RET_VAL=\"$?\" && env > /tmp/cbl_env && exit $_CBL_RET_VAL"
      ]
    end

    def self.print_out lines
      lines.each{|l| puts l}
    end
  end
end

