lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'fastlane/plugin/translate_gpt/version'

Gem::Specification.new do |spec|
  spec.name          = 'fastlane-plugin-translate_gpt'
  spec.version       = Fastlane::TranslateGpt::VERSION
  spec.author        = 'Aleksei Cherepanov'
  spec.email         = 'ftp27host@gmail.com'

  spec.summary       = 'This fastlane plugin provides an easy way to use the OpenAI GPT language model to translate strings in your iOS application.'
  spec.homepage      = 'https://github.com/ftp27/fastlane-plugin-translate_gpt'
  spec.license       = 'MIT'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ftp27/fastlane-plugin-translate_gpt'
  spec.metadata['github_repo'] = 'https://github.com/ftp27/fastlane-plugin-translate_gpt'

  spec.files         = Dir['lib/**/*'] + %w[README.md LICENSE]
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.6'

  spec.add_runtime_dependency 'loco_strings', '~> 0.1.5'
  spec.add_runtime_dependency 'ruby-openai', '~> 3.7'

  spec.add_development_dependency('bundler')
  spec.add_development_dependency('fastlane', '>= 2.212.2')
  spec.add_development_dependency('pry')
  spec.add_development_dependency('rake')
  spec.add_development_dependency('rspec')
  spec.add_development_dependency('rspec_junit_formatter')
  spec.add_development_dependency('rubocop', '1.12.1')
  spec.add_development_dependency('rubocop-performance')
  spec.add_development_dependency('rubocop-require_tools')
  spec.add_development_dependency('simplecov')
end
