require 'spec_helper'
require 'docker'

CLI = CodeBuildLocal::CLI
DefaultImages = CodeBuildLocal::DefaultImages

RSpec.describe CLI do

  FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures/cli/project_folder")

  TEST_PATH = FIXTURES_PATH
  TEST_BUILD_SPEC_PATH = './foo/bar/spec.yml'
  TEST_IMAGE = 'some_id'
  TEST_AWS_DOCKERFILE_PATH = 'ubuntu/java/openjdk-8'

  class TestCLI < CLI
    attr_accessor :runner

    def make_runner opts
      @runner.initialize opts
      @runner
    end
  end

  def make_cli argv
    cli = TestCLI.new argv
    runner = double("runner")
    allow(runner).to receive(:initialize)
    cli.runner = runner
    cli
  end

  describe "#run" do
    context "Default" do
      before :each do
        @cli = make_cli ["-p", TEST_PATH]
        allow(@cli.runner).to receive(:run) {|im, sp, opts| @im = im ; @sp = sp ; @opts = opts}
        @cli.run
      end

      it "Is not quiet" do
        expect(@cli.runner).to have_received(:initialize).with(hash_including(:quiet => false))
      end

      it "Uses default image" do
        expect(@im.id).to eq(DefaultImages.build_code_build_image.id)
      end

      it "Doesnt override build_spec_path" do
        expect(@opts).to have_key(:build_spec_path)
        expect(@opts[:build_spec_path]).to be_nil 
      end

      it "Uses specified path" do
        expect(@sp.path).to eq(TEST_PATH)
      end
    end

    context "Parameters" do
      it "Supports alternate build spec path" do
        @cli = make_cli ["-p", TEST_PATH, "--build_spec_path", TEST_BUILD_SPEC_PATH]
        allow(@cli.runner).to receive(:run){|im, sp, opts| @im = im ; @sp = sp ; @opts = opts}
        @cli.run
        expect(@opts[:build_spec_path]).to eq(TEST_BUILD_SPEC_PATH)
      end

      it "Supports alternate image" do
        image = Docker::Image.get(Docker::Image.build("from alpine\nrun touch /test").id)
        @cli = make_cli ["-p", TEST_PATH, "--image_id", image.id]
        allow(@cli.runner).to receive(:run){|im, sp, opts| @im = im ; @sp = sp ; @opts = opts}
        @cli.run
        expect(@im.id).to eq(image.id)
      end

      it "Supports alternate AWS Dockerfile" do
        image = DefaultImages.build_code_build_image :aws_dockerfile_path => TEST_AWS_DOCKERFILE_PATH
        @cli = make_cli ["-p", TEST_PATH, "--aws_dockerfile_path", TEST_AWS_DOCKERFILE_PATH]
        allow(@cli.runner).to receive(:run){|im, sp, opts| @im = im ; @sp = sp ; @opts = opts}
        @cli.run
        expect(@im.id).to eq(image.id)
      end

      it "Supports quiet" do
        @cli = make_cli ["-p", TEST_PATH, "-q"]
        allow(@cli.runner).to receive(:run)
        @cli.run
        expect(@cli.runner).to have_received(:initialize).with(hash_including(:quiet => true))
      end
    end
  end

  # it's hard to inject test dependencies in a main function, so just test that it outputs what we expect
  describe ".main" do
    it "works as expected" do
      # ignore warning for redefining ARGV constant
      warn_level = $VERBOSE
      $VERBOSE = nil
      ARGV = ['-p', TEST_PATH, '--quiet']
      $VERBOSE = warn_level
      expect {expect {CLI.main}.to output("value1\nvalue2\nvalue3\nvalue4\n").to_stdout}.to output("err1\nerr2\nerr3\nerr4\n").to_stderr
    end
  end
end
