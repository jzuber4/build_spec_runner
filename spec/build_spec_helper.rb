require 'code_build_local'
require 'tempfile'

BuildSpec = CodeBuildLocal::BuildSpec::BuildSpec

module BuildSpecHelper

  def self.make_version version
    "version: #{version}\n"
  end

  def self.make_env env
    output = "env:\n"
    if env.has_key? :variables
      variables = env[:variables]
      output << "  variables:\n"
      variables.keys.each{|k| output << "    #{k}: #{variables[k]}\n"}
    end
    if env.has_key? :parameter_store
      params = env[:parameter_store]
      output << "  parameter-store:\n"
      params.keys.each{|k| output << "    #{k}: #{params[k]}\n"}
    end
    output
  end

  def self.make_phase phase, commands
    output = "  #{phase}:\n"
    unless commands.nil?
      output << "    commands:\n"
      commands.each{|cmd| output << "      - #{cmd}\n"}
    end
    output
  end

  def self.make_phases phases
    output = "phases:\n"
    phases.keys.each{|p| output << make_phase(p, phases[p])}
    output
  end

  def self.make_artifacts files, discard_paths, base_directory
    output = "artifacts:\n"
    unless files.nil?
      output << "  files:\n"
      files.each{|file| output << "    - #{file}\n"}
    end
    unless discard_paths.nil?
      output << "  discard-paths: #{discard_paths}\n"
    end
    unless base_directory.nil?
      output << "  base-directory: #{base_directory}\n"
    end
    output
  end

  def self.make_buildspec_string opts
    output = ""
    output << make_version(opts[:version]) unless opts[:version].nil?
    output << make_env(opts[:env]) unless opts[:env].nil?
    output << make_phases(opts[:phases]) unless opts[:phases].nil?
    unless opts[:artifacts].nil?
      output << make_artifacts(
        opts[:artifacts][:files],
        opts[:artifacts]['discard-paths'.to_sym],
        opts[:artifacts]['base-directory'.to_sym],
      )
    end
    output
  end

  def self.make_buildspec_file contents
    file = Tempfile.new
    File.open(file, 'w') {|f| f.write(contents)}
    file.path
  end

  def self.make_buildspec opts
    BuildSpec.new(make_buildspec_file(make_buildspec_string(opts)))
  end
end
