require 'aws-sdk-core'
require 'spec_helper'
require 'docker'

CLI = BuildSpecRunner::CLI
DefaultImages = BuildSpecRunner::DefaultImages

RSpec.describe CLI do

  FIXTURES_PATH = File.join(File.dirname(__FILE__), "fixtures/cli/project_folder")

  TEST_PATH = FIXTURES_PATH
  TEST_BUILD_SPEC_PATH = './foo/bar/spec.yml'
  TEST_IMAGE = 'some_id'
  TEST_AWS_DOCKERFILE_PATH = 'ubuntu/ruby/2.2.5'
  SSM_VALUE = 'expected this value'

  def mock_runner
    runner = class_double("BuildSpecRunner::Runner").as_stubbed_const(:transfer_nested_constants => true)
    allow(runner).to receive(:run) {|im, sp, opts| @im = im ; @sp = sp ; @opts = opts}
    runner
  end

  describe "#run" do
    context "Default" do
      before :each do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH]
        @cli.run
      end

      it "Uses default image" do
        expect(@im.id).to eq(DefaultImages.build_image.id)
      end

      it "Uses specified path" do
        expect(@sp.path).to eq(TEST_PATH)
      end

      it "Is not quiet" do
        expect(@opts).to_not have_key(:quiet) 
      end

      it "Doesnt override build_spec_path" do
        expect(@opts).to_not have_key(:build_spec_path)
      end
    end

    context "Parameters" do
      it "Supports alternate build spec path" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--build_spec_path", TEST_BUILD_SPEC_PATH]
        @cli.run
        expect(@opts[:build_spec_path]).to eq(TEST_BUILD_SPEC_PATH)
      end

      it "Supports alternate image" do
        @runner = mock_runner
        image = Docker::Image.get(Docker::Image.build("from alpine\nrun touch /test").id)
        @cli = CLI.new ["-p", TEST_PATH, "--image_id", image.id]
        @cli.run
        expect(@im.id).to eq(image.id)
      end

      it "Supports alternate AWS Dockerfile" do
        @runner = mock_runner
        image = DefaultImages.build_image :aws_dockerfile_path => TEST_AWS_DOCKERFILE_PATH
        @cli = CLI.new ["-p", TEST_PATH, "--aws_dockerfile_path", TEST_AWS_DOCKERFILE_PATH]
        @cli.run
        expect(@im.id).to eq(image.id)
      end

      it "Supports quiet" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "-q"]
        @cli.run
        expect(@opts).to have_key(:quiet)
        expect(@opts[:quiet]).to be_truthy

        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--quiet"]
        @cli.run
        expect(@opts).to have_key(:quiet)
        expect(@opts[:quiet]).to be_truthy
      end

      it "Supports no_credentials" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--no_credentials"]
        @cli.run
        expect(@opts).to have_key(:no_credentials)
        expect(@opts[:no_credentials]).to be_truthy
      end

      it "Supports profile" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--profile", "bob"]
        @cli.run

        expect(@opts).to have_key(:profile)
        expect(@opts[:profile]).to eq("bob")
      end

      it "Supports region" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--region", "us-south-8"] # the ocho
        @cli.run

        expect(@opts).to have_key(:region)
        expect(@opts[:region]).to eq("us-south-8")
      end
    end

    context "Invalid invocations" do
      it "profile and no_credentials" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--profile", "thebuilder", "--no_credentials"]
        expect {@cli.run} .to raise_error(OptionParser::InvalidOption)
      end

      it "aws_dockerfile_path and image_id" do
        @runner = mock_runner
        @cli = CLI.new ["-p", TEST_PATH, "--aws_dockerfile_path", "windows/98/fortran-0.1", "-i", "0xdeadbeef"]
        expect {@cli.run} .to raise_error(OptionParser::InvalidOption)
      end

      it "no path" do
        @runner = mock_runner
        @cli = CLI.new []
        expect {@cli.run} .to raise_error(OptionParser::MissingArgument)
      end
    end
  end

  let(:stub_ssm) do
    stub_ssm
  end

  # it's hard to inject test dependencies in a main function, so just test that it outputs what we expect
  describe ".main" do

    let(:stub_ssm) { Aws::SSM::Client.new(stub_responses: true) }
    it "works as expected" do
      stub_ssm.stub_responses(:get_parameter, { :parameter => { :value => SSM_VALUE } })
      # 2 times -> once for actual getting of parameters, once for a hack to get the default region
      expect(Aws::SSM::Client).to receive(:new).and_return(stub_ssm, stub_ssm)

      # ignore warning for redefining ARGV constant
      warn_level = $VERBOSE
      $VERBOSE = nil
      ARGV = ['-p', TEST_PATH, '--quiet']
      $VERBOSE = warn_level
      expect {expect {CLI.main}.to output("value1\nvalue2\n#{SSM_VALUE}\nvalue3\nvalue4\n").to_stdout}.to output("err1\nerr2\nerr3\nerr4\n").to_stderr
    end
  end
end
