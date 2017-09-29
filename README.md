# CodeBuildLocal

[![Gem Version](https://img.shields.io/gem/v/code_build_local.svg)](https://rubygems.org/gems/code_build_local)
[![Code Climate](https://img.shields.io/codeclimate/github/jzuber4/code_build_local.svg)](https://codeclimate.com/github/jzuber4/code_build_local)
[![Gemnasium](https://img.shields.io/gemnasium/jzuber4/code_build_local.svg)](https://gemnasium.com/github.com/jzuber4/code_build_local/)

CodeBuildLocal is a utility for reproducing [AWS CodeBuild](https://aws.amazon.com/codebuild/) executions locally. It does so by running the CodeBuild project locally with Docker, trying to mirror the execution semantics of CodeBuild as much as possible. It is primarily useful as a CLI utility but can also be used as a library.

Currently *unsupported* features:

* Build artifact export -- CodeBuildLocal will not export your build artifacts. It essentially ignores the "artifacts" section of the Build Spec file.
* [Build Environment Variables](http://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-env-vars.html) -- CodeBuildLocal does not specify all the same environment variables as AWS CodeBuild. It does support environment variables declared in the Build Spec file.

## Installation

### Dependencies

CodeBuildLocal requires Docker. See the [Docker installation instructions](https://docs.docker.com/engine/installation/).
If you wish to be able to execute docker without root, you may want to follow the [Linux Post-Installation Instructions](https://docs.docker.com/engine/installation/linux/linux-postinstall/). Please be aware of the security risks of doing so.

CodeBuildLocal tries to attach [AWS STS](http://docs.aws.amazon.com/STS/latest/APIReference/Welcome.html) credentials to the Docker container by default. It is recommended that you [configure the AWS CLI](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-started.html) to enable this functionality. This lets you run any actions in your CodeBuild project that require AWS authentication. You may choose the AWS profile to use, otherwise it falls back to the configured default.

### CLI utility installation

    $ gem install code_build_local

### Library installation

Add this line to your application's Gemfile:

```ruby
gem 'code_build_local'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install code_build_local

## Usage

Execute a CodeBuild project located at a directory, given the default ```buildspec.yml``` Build Spec filename:

    $ code_build_local -p /path/to/project/

Specify a different Build Spec filepath with ```--build_spec_path```:

    $ code_build_local -p /path/to/project/ --build_spec_path ./my_build_spec_so_unique.yml

Relative and absolute paths are OK:

    $ code_build_local -p ../project/ --build_spec_path /path/to/build/spec/bs.yml

You can silence CodeBuildLocal's debug output with ```-q``` or ```--quiet```:

    $ code_build_local -p /path/to/project/ --quiet

Specify your own Docker image by its ID with ```--image_id```:

    $ code_build_local -p /path/to/project/ --image_id fee13e06bbce

Specify a different AWS CodeBuild vended image with ```--aws_dockerfile_path```. See the official [AWS CodeBuild Docker images repo](https://github.com/aws/aws-codebuild-docker-images) for more information:

    $ code_build_local -p /path/to/project/ --aws_dockerfile_path ubuntu/java/openjdk-8

By default CodeBuildLocal will use the configured default AWS profile. Specify a different profile with ```--profile```:

    $ code_build_local -p /path/to/project/ --profile MyBuilderBot

By default CodeBuildLocal will attach AWS STS credentials for the current default AWS profile to the CodeBuild project's Docker container.
You can opt out of this by passing ```--no_creds```:

    $ code_build_local -p /path/to/project/ --no_creds

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jzuber4/code_build_local. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the CodeBuildLocal project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/jzuber4/code_build_local/blob/master/CODE_OF_CONDUCT.md).
