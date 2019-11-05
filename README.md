# AutoRailsCleanup

A small set of utilities to help automatically clean up Rails Apps.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'auto_rails_cleanup'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install auto_rails_cleanup

## Basic Usage

Clone this repo, then bundle install, then reference locally for now. a CLI will be added.

### Cleaner

Pick a strategy build a verbose cleaner command

```
CIRCLE_JOBS="test_unit,system_tests,test_javascript,static_analysis" PROJECT_PATH=`pwd` CIRCLE_PROJECT=coverband_demo CIRCLE_ORG=coverband_service CIRCLE_TOKEN=XYZ VALIDATOR=LocalAndCircleValidator STRATEGY=DeletionStrategy DELETE_TARGET=/Users/danmayer/projects/dasher/app/assets/images/components/jewelry_tone_component/**/* TEST_TARGET="bundle exec rspec spec/system/billing_postcode_spec.rb" CIRCLE_BRANCH="auto_clean_images" ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/cleaner.rb
```

### CircleCI Runner

This allows running a CircleCI branch to test and verify CI passes.

```
CIRCLE_TOKEN=XYZ CIRCLE_ORG=coverband_service CIRCLE_PROJECT=coverband_demo CIRCLE_BRANCH="auto_clean_images" CIRCLE_JOBS="test_unit,system_tests,test_javascript,static_analysis" CIRCLE_RUNS=1 ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/runner.rb
```

### Git Cleaner

Clean a repo, compacting the successes and removing commits related to failed cleanup attempts...

`ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/git_cleaner.rb`

## Workflow Usage

1. find a good smoke test
2. review data select cleanup strategy
3. build out the cleaner command
4. review resulting commits
5. before sumbmitting a PR, git_cleanup

### 1. Find a Good Smoke Test

I find that a system test that hits some assets (forcing asset build), works well. I generally when running with local and CI, run a single fast local test, allowing CI to run the full suite.

### 2. review data select cleanup strategy

TBD

### 3. build out the cleaner command

TBD

### 4. review resulting commits

TBD

### 5. Before Submitting a PR, git_cleanup

I find that all the commits that are tried and rolled back can be overwhelming for the code reviewers. I like all those commits as an author as they can help me investigate and do further targetted cleaning myself... When it is time to review, I prefer to collapse all the failed attempts out of the PR. To do that run the Git Cleaner script mentioned in the usage section.


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/auto_rails_cleanup. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the AutoRailsCleanup project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/auto_rails_cleanup/blob/master/CODE_OF_CONDUCT.md).
