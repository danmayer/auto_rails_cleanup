lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "auto_rails_cleanup/version"

Gem::Specification.new do |spec|
  spec.name          = "auto_rails_cleanup"
  spec.version       = AutoRailsCleanup::VERSION
  spec.authors       = ["Dan Mayer"]
  spec.email         = ["dan.mayer@gmail.com"]

  spec.summary       = %q{A small set of utilities to help automatically clean up Rails Apps}
  spec.description   = %q{A small set of utilities to help automatically clean up Rails Apps. Integrates with tests and CI}
  spec.homepage      = "https://github.com/danmayer/auto_rails_cleanup"
  spec.license       = "MIT"

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/danmayer/auto_rails_cleanup"
  spec.metadata["changelog_uri"] = "https://github.com/danmayer/auto_rails_cleanup/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_runtime_dependency 'activesupport'
end
