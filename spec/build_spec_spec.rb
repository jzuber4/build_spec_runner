require 'build_spec_helper'
require 'spec_helper'

PHASES = BuildSpecRunner::BuildSpec::PHASES
BuildSpec = BuildSpecRunner::BuildSpec::BuildSpec
BuildSpecError = BuildSpecRunner::BuildSpec::BuildSpecError

RSpec.describe BuildSpec do

  def expect_buildspec_to_match_spec_opts buildspec, spec_opts
    PHASES.each do |phase|
        expect(buildspec.phases).to include(phase)
        expect(buildspec.phases[phase]).to eq(spec_opts[:phases][phase])
    end
  end

  def all_defined
    {
      :version => 0.2,
      :env => {
        :variables => { 'var1' => "value1", 'var2' => "value2", 'var3' => "value3", },
        :parameter_store => { 'param_one' => 'blabla', 'param_two' => 'blablabla' },
      },
      :phases => {
        'install'    => ['cmd1',  'cmd2',  'cmd3'],
        'pre_build'  => ['cmd4',  'cmd5',  'cmd6'],
        'build'      => ['cmd7',  'cmd8',  'cmd9'],
        'post_build' => ['cmd10', 'cmd11', 'cmd12'],
      },
      :artifacts => { :files => ['file1', 'file2',], 'base-directory'.to_sym => '/some/path', 'discard-paths'.to_sym => 'false' }
    }
  end

  context "Everything defined" do
    before :all do
      @spec_opts = all_defined
      @buildspec = BuildSpecHelper.make_buildspec @spec_opts
    end

    it "has env" do
      expect(@buildspec.env).to eq(@spec_opts[:env][:variables])
    end

    it "has parameter-store" do
      expect(@buildspec.parameter_store).to eq(@spec_opts[:env][:parameter_store])
    end

    it "has all phases" do
      expect_buildspec_to_match_spec_opts @buildspec, @spec_opts
    end
  end

  context "Optional entries" do
    it "has empty env" do
      spec_opts = all_defined.tap{|o| o.delete(:env)}
      buildspec = BuildSpecHelper.make_buildspec spec_opts
      expect(buildspec.env).to eq({})
    end

    it "Missing each phase" do
      PHASES.each do |phase|
        spec_opts = all_defined.tap{|o| o[:phases].delete(phase)}
        buildspec = BuildSpecHelper.make_buildspec spec_opts
        expect(buildspec.phases[phase]).to eq([])
      end
    end

    # These aren't currently in the buildspec API, so just check that it parses correctly

    it "has no parameter-store variables" do
      spec_opts = all_defined.tap{|o| o[:env].delete(:parameter_store)}
      BuildSpecHelper.make_buildspec spec_opts
    end

    it "Missing artifacts" do
      spec_opts = all_defined.tap{|o| o.delete(:artifacts)}
      BuildSpecHelper.make_buildspec spec_opts
    end

    it "Missing artifacts discard-paths" do
      spec_opts = all_defined.tap{|o| o[:artifacts].delete('discard-paths'.to_sym)}
      BuildSpecHelper.make_buildspec spec_opts
    end

    it "Missing artifacts base-directory" do
      spec_opts = all_defined.tap{|o| o.delete('base-directory'.to_sym)}
      BuildSpecHelper.make_buildspec spec_opts
    end
  end

  context "Invalid formats" do
    BASE_BAD_FILE_CONTENTS = "version: 0.2\nphases:\n  install:\n    commands:\n      - echo hello\n"
    
    # check that our starter string isn't triggering errors
    it "Parses base OK" do
      BuildSpec.new(BuildSpecHelper.make_buildspec_file(BASE_BAD_FILE_CONTENTS))
    end

    it "Unknown top level key" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "unknown:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Invalid version" do
      spec_opts = all_defined.tap{|o| o[:version] = 0.1}
      expect{BuildSpecHelper.make_buildspec spec_opts}.to raise_error(BuildSpecError)
    end

    it "Missing version" do
      spec_opts = all_defined.tap{|o| o.delete(:version)}
      expect{BuildSpecHelper.make_buildspec spec_opts}.to raise_error(BuildSpecError)
    end

    it "Missing phases" do
      spec_opts = all_defined.tap{|o| o.delete(:phases)}
      expect{BuildSpecHelper.make_buildspec spec_opts}.to raise_error(BuildSpecError)
    end

    it "Unknown phase" do
      spec_opts = all_defined.tap{|o| o[:phases][:recombobulate] = ["wow"]}
      expect{BuildSpecHelper.make_buildspec spec_opts}.to raise_error(BuildSpecError)
    end

    it "Missing phase command" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "  build:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Empty phase command" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "  build:\n    commands:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Unknown key under phase"  do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "  build:\n    commands:\n      - test\n    unknown:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non string phase command" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "  build:\n    commands:\n      mapping: value\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Missing env mappings" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Empty env variables" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n  variables:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non string variable under env" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n  variables:\n    variable:\n      mapping: true\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Empty env parameter-store" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n  variables:\n    variable: bla\n  parameter-store:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non string variable under parameter-store" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n  variables:\n    variable: bla\n  parameter-store:\n    mapping: true\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Unknown key under env"  do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "env:\n  unknown:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Missing artifacts files" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "artifacts:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    BASE_ARTIFACTS_FILES = BASE_BAD_FILE_CONTENTS + "artifacts:\n  files:\n    - files1\n"
    it "Base artifacts files works" do
      buildspec_file = BuildSpecHelper.make_buildspec_file BASE_ARTIFACTS_FILES
      BuildSpec.new buildspec_file
    end

    it "Empty artifacts files" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "artifacts:\n  files:\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non array artifacts files" do
      bad_file_contents = BASE_BAD_FILE_CONTENTS + "artifacts:\n  files:\n    mapping: true\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Unknown key under artifacts" do
      bad_file_contents = BASE_ARTIFACTS_FILES + "  unknown:\n\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non boolean discard-paths" do
      bad_file_contents = BASE_ARTIFACTS_FILES + "  discard-paths: 7"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end

    it "Non string base-directory" do
      bad_file_contents = BASE_ARTIFACTS_FILES + "  base-directory:\n    mapping: true\n"
      buildspec_file = BuildSpecHelper.make_buildspec_file bad_file_contents
      expect{BuildSpec.new buildspec_file}.to raise_error(BuildSpecError)
    end
  end
end
