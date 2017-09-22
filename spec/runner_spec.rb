require 'spec_helper'
require 'pathname'

Runner = CodeBuildLocal::Runner
DefaultImages = CodeBuildLocal::DefaultImages
FolderSourceProvider = CodeBuildLocal::SourceProvider::FolderSourceProvider

RSpec.describe Runner do

  FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures/runner")

  def make_runner opts={}
    Runner.new(opts.merge({
      :outstream => StringIO.new,
      :errstream => StringIO.new,
    }))
  end

  before :all do
    @default_image = DefaultImages.build_code_build_image
  end

  describe "#run_default" do

    DEFAULT_DIR = File.join(FIXTURES_PATH, "default_name")

    context "Basic Run" do
      before :all do
        @runner = make_runner
        @exit_code = @runner.run_default(DEFAULT_DIR)
      end

      it "executes phases" do
        expect(@runner.outstream.string).to eq("value1\nvalue2\nvalue3\nvalue4\n")
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs to stderr" do
        filtered_lines = @runner.errstream.string
            .split("\n")
            .reject{|line| line =~ /^\[CodeBuildLocal Runner\]/}
            .join("\n")
        expect(filtered_lines).to eq("err1\nerr2\nerr3\nerr4")
      end

      it "outputs debug phase messages" do
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running phase "build"')
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running phase "post_build"')
      end

      it "outputs debug command messages" do
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR1"')
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR2"')
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR3"')
        expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR4"')
      end
    end
  end

  describe "#run" do

    JAVA_IMAGE_DIR = File.join(FIXTURES_PATH, "java_image")
    CUSTOM_BUILDSPEC_NAME_DIR = File.join(FIXTURES_PATH, "custom_name")
    ECHO_CREDS_DIR = File.join(FIXTURES_PATH, "echo_creds")
    FILES_DIR = File.join(FIXTURES_PATH, "files")
    SHELL_ATTRIBUTES_DIR = File.join(FIXTURES_PATH, "shell")

    context "Quiet" do
      before :all do
        @runner = make_runner :quiet => true
        image = DefaultImages.build_code_build_image
        @exit_code = @runner.run(image, FolderSourceProvider.new(DEFAULT_DIR))
      end

      it "exits succesfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs correct stdout and stderr" do
        expect(@runner.outstream.string).to eq("value1\nvalue2\nvalue3\nvalue4\n")
        expect(@runner.errstream.string).to eq("err1\nerr2\nerr3\nerr4\n")
      end

      it "doesn't output debug messages" do
        expect(@runner.errstream.string).to_not include("[CodeBuildLocal Runner]")
      end
    end

    context "Relative source provider path" do
      before :all do
        @runner = make_runner
        relative_dir = (Pathname.new DEFAULT_DIR).relative_path_from(Pathname.new Dir.pwd)
        image = DefaultImages.build_code_build_image
        @exit_code = @runner.run(image, FolderSourceProvider.new(relative_dir))
      end

      it "exits succesfully" do
        expect(@exit_code).to eq(0)
      end

      it "outputs correct stdout" do
        expect(@runner.outstream.string).to eq("value1\nvalue2\nvalue3\nvalue4\n")
      end
    end

    context "Custom image" do
      before :all do
        @runner = make_runner
        image = DefaultImages.build_code_build_image({:aws_dockerfile_path => 'ubuntu/java/openjdk-8'})
        @exit_code = @runner.run(image, FolderSourceProvider.new(JAVA_IMAGE_DIR))
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.errstream.string).to include('openjdk version "1.8')
        expect(@runner.errstream.string).to include('OpenJDK Runtime Environment')
        expect(@runner.errstream.string).to include('OpenJDK 64-Bit Server VM')
      end
    end

    context "Custom buildspec name" do
      before :all do
        @runner = make_runner
        image = DefaultImages.build_code_build_image
        build_spec_path = "my_spec_file.yml"
        @exit_code = @runner.run(image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.outstream.string).to eq("so predictable\n")
      end
    end

    context "No credentials" do
      before :all do
        @runner = make_runner :no_credentials => true
        @exit_code = @runner.run(DefaultImages.build_code_build_image, FolderSourceProvider.new(ECHO_CREDS_DIR))
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.outstream.string).to eq("\n\n\n") # no credentials to echo!
      end
    end

    context "Custom STS client" do
      # test exit code and output here, since CodeBuild runs are expensive and mocks shouldn't live outside of a single test execution
      it "exits successfully and yields correct output" do
        # expected key/secret/token
        @aws_key = "not so secret key"
        @aws_secret = "very secret, shhh!!"
        @aws_token = "token/token/token/token/token/token/token/token/token/token/token/token/..."

        # make mock client
        @sts_client = double("sts_client")
        @creds = double("credentials")
        allow(@creds).to receive(:credentials) { { "AWS_ACCESS_KEY_ID" => @aws_key, "AWS_SECRET_ACCESS_KEY" => @aws_secret, "AWS_SESSION_TOKEN" => @aws_token} }
        allow(@sts_client).to receive(:get_session_token) { @creds }

        # make runner and execute
        @runner = make_runner :sts_client => @sts_client
        @exit_code = @runner.run(DefaultImages.build_code_build_image, FolderSourceProvider.new(ECHO_CREDS_DIR))

        # expect
        expect(@creds).to have_received(:credentials).with(no_args)
        expect(@sts_client).to have_received(:get_session_token).with(no_args)
        expect(@exit_code).to eq(0)
        expect(@runner.outstream.string).to eq("\n\n\n") # no credentials to echo!
      end
    end

    context "Custom buildspec name with relative path" do
      before :all do
        @runner = make_runner
        build_spec_path = "another_path/file_mcfile_face.yml"
        @exit_code = @runner.run(@default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.outstream.string).to eq("we can go deeper\n")
      end
    end

    context "Custom buildspec name with absolute path" do
      before :all do
        @runner = make_runner
        build_spec_path = File.join(CUSTOM_BUILDSPEC_NAME_DIR, "another_path/file_mcfile_face.yml")
        @exit_code = @runner.run(@default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), :build_spec_path => build_spec_path)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.outstream.string).to eq("we can go deeper\n")
      end
    end

    context "Copies over project" do
      before :all do
        @runner = make_runner
        @exit_code = @runner.run(@default_image, FolderSourceProvider.new(FILES_DIR))
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "sees both files" do
        expect(@runner.outstream.string).to eq("File 1's Contents\nFile 2's Contents\n")
      end
    end

    # Right now we do some hacks to make it look like there's only one shell session, it might be
    # nice to actually implement it as one shell session
    context "Shell session attributes" do
      before :all do
        @runner = make_runner
        @exit_code = @runner.run(@default_image, FolderSourceProvider.new(SHELL_ATTRIBUTES_DIR))
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "Remembers env variables" do
        expect(@runner.outstream.string).to include("ENV VALUE = VALUE OF ENV")
      end

      it "Remembers local variables" do
        expect(@runner.outstream.string).to include("LOCAL VALUE = VALUE OF LOCAL")
      end

      it "Remembers directory" do
        expect(@runner.outstream.string).to include("/usr/app/folder_within_project")
      end
    end

    context "Failures" do

      FAILURES_DIR = File.join(FIXTURES_PATH, "failures")

      context "at install" do
        before :all do
          @runner = make_runner
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "install"))
          @exit_code = @runner.run(@default_image, source_provider)
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "only runs install" do
          expect(@runner.errstream.string).to include('[CodeBuildLocal Runner] Running phase "install"')
          expect(@runner.outstream.string).to include('ran install')
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
          expect(@runner.errstream.string).not_to include('[CodeBuildLocal Runner] Running phase "pre_build"')
          expect(@runner.errstream.string).not_to include('[CodeBuildLocal Runner] Running phase "build"')
          expect(@runner.errstream.string).not_to include('[CodeBuildLocal Runner] Running phase "post_build"')
        end
      end

      context "at pre_build" do
        before :all do
          @runner = make_runner
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "pre_build"))
          @exit_code = @runner.run(@default_image, source_provider)
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs install and pre_build" do
          ['install', 'pre_build'].each do |phase|
            expect(@runner.errstream.string).to include("[CodeBuildLocal Runner] Running phase \"#{phase}\"")
            expect(@runner.outstream.string).to include("ran #{phase}")
          end
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
        end
      end

      context "at build" do
        before :all do
          @runner = make_runner
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "build"))
          @exit_code = @runner.run(@default_image, source_provider)
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs all phases" do
          CodeBuildLocal::BuildSpec::PHASES.each do |phase|
            expect(@runner.errstream.string).to include("[CodeBuildLocal Runner] Running phase \"#{phase}\"")
            expect(@runner.outstream.string).to include("ran #{phase}")
          end
        end
      end

      context "at post_build" do
        before :all do
          @runner = make_runner
          source_provider = FolderSourceProvider.new(File.join(FAILURES_DIR, "post_build"))
          @exit_code = @runner.run(@default_image, source_provider)
        end

        it "exits with failure" do
          expect(@exit_code).to eq(1)
        end

        it "doesnt run command after failed command" do
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS COMMAND")
        end

        it "Runs all phases" do
          CodeBuildLocal::BuildSpec::PHASES.each do |phase|
            expect(@runner.errstream.string).to include("[CodeBuildLocal Runner] Running phase \"#{phase}\"")
            expect(@runner.outstream.string).to include("ran #{phase}")
          end
        end
      end
    end
  end
end
