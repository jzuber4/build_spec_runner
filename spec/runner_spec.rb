require 'spec_helper'

Runner = CodeBuildLocal::Runner
DefaultImages = CodeBuildLocal::DefaultImages
FolderSourceProvider = CodeBuildLocal::SourceProvider::FolderSourceProvider

RSpec.describe Runner do

  FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures/runner")

  def make_runner
    Runner.new({
      :outstream => StringIO.new,
      :errstream => StringIO.new,
    })
  end

  before :all do
    @default_image = DefaultImages.build_code_build_image
  end

  describe "#run_default" do

    DEFAULT_BUILDSPEC_DIR = File.join(FIXTURES_PATH, "default_name")

    context "Basic Run" do
      before :all do
        @runner = make_runner
        @exit_code = @runner.run_default(DEFAULT_BUILDSPEC_DIR)
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

    JAVA_IMAGE_BUILDSPEC_DIR = File.join(FIXTURES_PATH, "java_image")
    CUSTOM_BUILDSPEC_NAME_DIR = File.join(FIXTURES_PATH, "custom_name")
    FILES_DIR = File.join(FIXTURES_PATH, "files")
    SHELL_ATTRIBUTES_DIR = File.join(FIXTURES_PATH, "shell")

    context "Custom image" do
      before :all do
        @runner = make_runner
        image = DefaultImages.build_code_build_image({:dockerfile_path => 'ubuntu/java/openjdk-8'})
        @exit_code = @runner.run(image, FolderSourceProvider.new(JAVA_IMAGE_BUILDSPEC_DIR))
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
        buildspec_path = "my_spec_file.yml"
        @exit_code = @runner.run(image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), buildspec_path)
      end

      it "exits successfully" do
        expect(@exit_code).to eq(0)
      end

      it "yields correct output" do
        expect(@runner.outstream.string).to eq("so predictable\n")
      end
    end

    context "Custom buildspec name with path" do
      before :all do
        @runner = make_runner
        buildspec_path = "another_path/file_mcfile_face.yml"
        @exit_code = @runner.run(@default_image, FolderSourceProvider.new(CUSTOM_BUILDSPEC_NAME_DIR), buildspec_path)
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
