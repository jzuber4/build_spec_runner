# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "build_spec_runner/version"

Gem::Specification.new do |spec|
  spec.name          = "build_spec_runner"
  spec.version       = BuildSpecRunner::VERSION
  spec.authors       = ["Jimmy Zuber"]
  spec.email         = ["jzuber4@gmail.com"]

  spec.summary       = %q{A gem to execute AWS CodeBuild build_spec.yml files locally.}
  spec.description   = %q{A gem to execute AWS CodeBuild build_spec.yml files locally.
AWS CodeBuild (https://aws.amazon.com/codebuild/) is an AWS product. This gem is a third-party creation not affiliated with AWS.
}
  spec.homepage      = "https://github.com/jzuber4/build_spec_runner"
  spec.license       = "MIT"

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'aws-sdk-core', '~> 3'
  spec.add_dependency 'aws-sdk-ssm', '~> 1.1'
  spec.add_dependency 'docker-api', '~> 1.33'
  spec.add_dependency 'git', '~> 1.3'
  spec.add_dependency 'kwalify', '~> 0.7'
  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency 'pry', '~> 0.11'
  spec.add_development_dependency "rake", "~> 12.1"
  spec.add_development_dependency "rspec", "~> 3.6"
  spec.add_development_dependency "yard", "~> 0.9"
end
