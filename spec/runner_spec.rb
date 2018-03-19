require 'spec_helper'
require 'pathname'

Runner = BuildSpecRunner::Runner
DefaultImages = BuildSpecRunner::DefaultImages
FolderSourceProvider = BuildSpecRunner::SourceProvider::FolderSourceProvider

RSpec.describe Runner do

  FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures/runner")

  SSM_VALUES = ["ssm value 1", "ssm value 2", "ssm value 3", "ssm value 4"]

  def add_streams opts
    @outstream = StringIO.new
    @errstream = StringIO.new
    opts.merge({
      :outstream => @outstream,
      :errstream => @errstream,
    })
  end

  def run image, source_provider, opts={}
    Runner.run image, source_provider, add_streams(opts)
  end

  def run_default path, opts={}
    Runner.run_default path, add_streams(opts)
  end

  before :all do
    @default_image = DefaultImages.build_image

    Aws.config[:ssm] = {
      :stub_responses => {
        :get_parameter => [
          { :parameter => { :value => SSM_VALUES[0] } },
          { :parameter => { :value => SSM_VALUES[1] } },
          { :parameter => { :value => SSM_VALUES[2] } },
          { :parameter => { :value => SSM_VALUES[3] } },
        ]
      }
    }

    @default_output = "value1\nvalue2\n#{SSM_VALUES[0]}\nvalue3\nvalue4\n"
  end

  describe "#run_default" do

    DEFAULT_DIR = File.join(FIXTURES_PATH, "default_name")

    context "Basic Run" do
      before :all do
        @exit_code = run_default(DEFAULT_DIR)
      end

      it "executes phases" do
        expect(@outstream.string).to eq(@default_output)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs to stderr" do
        filtered_lines = @errstream.string
            .split("\n")
            .reject{|line| line =~ /^\[BuildSpecRunner Runner\]/}
            .join("\n")
        expect(filtered_lines).to eq("err1\nerr2\nerr3\nerr4")
      end

      it "outputs debug phase messages" do
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running phase "build"')
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running phase "post_build"')
      end

      it "outputs debug command messages" do
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running command "echo $VAR1"')
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running command "echo $VAR2"')
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running command "echo $VAR3"')
        expect(@errstream.string).to include('[BuildSpecRunner Runner] Running command "echo $VAR4"')
      end
    end
  end

  describe "#run" do

    ALTERNATE_IMAGE_DIR = File.join(FIXTURES_PATH, "alternate_image")
    PARAMETER_STORE_DIR = File.join(FIXTURES_PATH, "parameter_store")
    CUSTOM_BUILDSPEC_NAME_DIR = File.join(FIXTURES_PATH, "custom_name")
    ECHO_CREDS_DIR = File.join(FIXTURES_PATH, "echo_creds")
    FILES_DIR = File.join(FIXTURES_PATH, "files")
    SHELL_ATTRIBUTES_DIR = File.join(FIXTURES_PATH, "shell")
    REGION_DIR = File.join(FIXTURES_PATH, "region")

    context "Quiet" do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(DEFAULT_DIR), :quiet => true
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs correct stdout and stderr" do
        expect(@outstream.string).to eq(@default_output)
        expect(@errstream.string).to eq("err1\nerr2\nerr3\nerr4\n")
      end

      it "doesn't output debug messages" do
        expect(@errstream.string).to_not include("[BuildSpecRunner Runner]")
      end
    end

    context "Region" do
      before :all do
        @region = 'ap-northeast-1'
        @exit_code = run @default_image, FolderSourceProvider.new(REGION_DIR), :region => @region
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs specified region" do
        expect(@outstream.string).to eq("#{@region}\n#{@region}\n")
      end
    end

    context "Default Region"  do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(REGION_DIR)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs specified region" do
        expect(@outstream.string).to match(/.+\n.+\n/)
      end
    end

    context "Relative source provider path" do
      before :all do
        relative_dir = (Pathname.new DEFAULT_DIR).relative_path_from(Pathname.new Dir.pwd)
        @exit_code = run @default_image, FolderSourceProvider.new(relative_dir)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs correct stdout" do
        expect(@outstream.string).to eq(@default_output)
      end
    end

    context "Custom image" do
      before :all do
        image = DefaultImages.build_image({:aws_dockerfile_path => 'ubuntu/ruby/2.2.5'})
        @exit_code = run image, FolderSourceProvider.new(ALTERNATE_IMAGE_DIR)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to include('ruby 2.2.5')
      end
    end

    context "Parameter store" do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(PARAMETER_STORE_DIR)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to eq(SSM_VALUES.join("\n") + "\n")
      end
    end

    context "Custom buildspec name" do
      before :all do
        build_spec_path = "my_spec_file.yml"
        @exit_code = run @default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to eq("so predictable\n")
      end
    end

    context "No credentials" do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(ECHO_CREDS_DIR), :no_credentials => true
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to eq("\n\n\n") # no credentials to echo!
      end
    end

    context "Custom profile" do
      # test exit code and output here, since runs are expensive and mocks shouldn't live outside of a single test execution
      it "exits successfully and yields correct output" do
        profile = "expected profile"

        stub_sts = Aws::STS::Client.new(stub_responses: true)
        expect(Aws::STS::Client).to receive(:new).with(hash_including(:profile => profile)).and_return(stub_sts)

        # expected key/secret/token
        @aws_key = "not so secret key"
        @aws_secret = "very secret, shhh!!"
        @aws_token = "token/token/token/token/token/token/token/token/token/token/token/token/..."

        # make mock client
        @creds = double("credentials")
        allow(@creds).to receive(:credentials) { { :access_key_id => @aws_key, :secret_access_key => @aws_secret, :session_token => @aws_token} }
        allow(stub_sts).to receive(:get_session_token) { @creds }

        # make runner and execute
        @exit_code = run @default_image, FolderSourceProvider.new(ECHO_CREDS_DIR), :profile => profile

        # expect
        expect(@creds).to have_received(:credentials).with(no_args)
        expect(stub_sts).to have_received(:get_session_token).with(no_args)
        expect(@exit_code).to eq(0)
        expect(@outstream.string).to eq("#{@aws_key}\n#{@aws_secret}\n#{@aws_token}\n")
      end
    end

    context "Custom buildspec name with relative path" do
      before :all do
        build_spec_path = "another_path/file_mcfile_face.yml"
        @exit_code = run @default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to eq("we can go deeper\n")
      end
    end

    context "Custom buildspec name with absolute path" do
      before :all do
        build_spec_path = File.join(CUSTOM_BUILDSPEC_NAME_DIR, "another_path/file_mcfile_face.yml")
        @exit_code = run @default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@outstream.string).to eq("we can go deeper\n")
      end
    end

    context "Copies over project" do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(FILES_DIR)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "sees both files" do
        expect(@outstream.string).to eq("File 1's Contents\nFile 2's Contents\n")
      end
    end

    # Right now we do some hacks to make it look like there's only one shell session, it might be
    # nice to actually implement it as one shell session
    context "Shell session attributes" do
      before :all do
        @exit_code = run @default_image, FolderSourceProvider.new(SHELL_ATTRIBUTES_DIR)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "Remembers env variables" do
        expect(@outstream.string).to include("ENV VALUE = VALUE OF ENV")
      end

      it "Remembers local variables" do
        expect(@outstream.string).to include("LOCAL VALUE = VALUE OF LOCAL")
      end

      it "Remembers directory" do
        expect(@outstream.string).to include("/usr/app/folder_within_project")
      end
    end

    context "Failures" do

      FAILURES_DIR = File.join(FIXTURES_PATH, "failures")

      context "at install" do
        before :all do
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "install"))
          @exit_code = run @default_image, source_provider
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "only runs install" do
          expect(@errstream.string).to include('[BuildSpecRunner Runner] Running phase "install"')
          expect(@outstream.string).to include('ran install')
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
          expect(@errstream.string).not_to include('[BuildSpecRunner Runner] Running phase "pre_build"')
          expect(@errstream.string).not_to include('[BuildSpecRunner Runner] Running phase "build"')
          expect(@errstream.string).not_to include('[BuildSpecRunner Runner] Running phase "post_build"')
        end
      end

      context "at pre_build" do
        before :all do
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "pre_build"))
          @exit_code = run @default_image, source_provider
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs install and pre_build" do
          ['install', 'pre_build'].each do |phase|
            expect(@errstream.string).to include("[BuildSpecRunner Runner] Running phase \"#{phase}\"")
            expect(@outstream.string).to include("ran #{phase}")
          end
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
        end
      end

      context "at build" do
        before :all do
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "build"))
          @exit_code = run @default_image, source_provider
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs all phases" do
          BuildSpecRunner::BuildSpec::PHASES.each do |phase|
            expect(@errstream.string).to include("[BuildSpecRunner Runner] Running phase \"#{phase}\"")
            expect(@outstream.string).to include("ran #{phase}")
          end
        end
      end

      context "at post_build" do
        before :all do
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "post_build"))
          @exit_code = run @default_image, source_provider
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs all phases" do
          BuildSpecRunner::BuildSpec::PHASES.each do |phase|
            expect(@errstream.string).to include("[BuildSpecRunner Runner] Running phase \"#{phase}\"")
            expect(@outstream.string).to include("ran #{phase}")
          end
        end
      end
    end
  end
end
