require 'colorize'
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
      :dbgstream => StringIO.new,
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
        expect(@runner.errstream.string).to eq("err1\nerr2\nerr3\nerr4\n")
      end

      it "outputs debug phase messages" do
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "install"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "pre_build"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "build"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "post_build"'.yellow)
      end

      it "outputs debug command messages" do
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR1"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR2"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR3"'.yellow)
        expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running command "echo $VAR4"'.yellow)
      end
    end
  end

  describe "#run" do

    JAVA_IMAGE_BUILDSPEC_DIR = File.join(FIXTURES_PATH, "java_image")
    CUSTOM_BUILDSPEC_NAME_DIR = File.join(FIXTURES_PATH, "custom_name")

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
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "install"'.yellow)
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
          expect(@runner.dbgstream.string).not_to include('[CodeBuildLocal Runner] Running phase "pre_build"'.yellow)
          expect(@runner.dbgstream.string).not_to include('[CodeBuildLocal Runner] Running phase "build"'.yellow)
          expect(@runner.dbgstream.string).not_to include('[CodeBuildLocal Runner] Running phase "post_build"'.yellow)
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
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "install"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "pre_build"'.yellow)
          expect(@runner.outstream.string).not_to eq("SHOULDNT SEE THIS PHASE")
          expect(@runner.dbgstream.string).not_to include('[CodeBuildLocal Runner] Running phase "build"'.yellow)
          expect(@runner.dbgstream.string).not_to include('[CodeBuildLocal Runner] Running phase "post_build"'.yellow)
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
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "install"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "pre_build"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "build"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "post_build"'.yellow)
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
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "install"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "pre_build"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "build"'.yellow)
          expect(@runner.dbgstream.string).to include('[CodeBuildLocal Runner] Running phase "post_build"'.yellow)
        end
      end
    end
  end
end
