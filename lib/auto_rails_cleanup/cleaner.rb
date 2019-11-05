require 'byebug'
require 'json'
require 'time'
require 'active_support/all'

#####
# This script takes input on a project to clean along with cleaning target(s).
#
# 1. The script will attempt to clean the target, via one of it's strategies
# 2. The script will then run a single test to verify the basics pass (like asset compilation)
# 3. The script then pushes the commit to CI and verfies it still passes, or it reverts it
# 4. Loops back to next file in the target
#
# execute:
# ruby circle_stats/cleaner.rb
# CIRCLE_TOKEN=YOUR_TOKEN VALIDATOR=CircleValidator ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/cleaner.rb
# CIRCLE_TOKEN=YOUR_TOKEN VALIDATOR=LocalAndCircleValidator ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/cleaner.rb
# PROJECT_PATH=`pwd` CIRCLE_TOKEN=YOUR_TOKEN TEST_TARGET="bundle exec rake" STRATEGY=CoverbandViewsStrategy DELETE_TARGET=~/Downloads/view_tracker_data.json ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/cleaner.rb
#
# How to use...
#
# 1. branch from master
# 2. run this script to clean as needed
# 3. verify things are passing and use the branch to review before PR
#
# TODOS:
#
# * blog
#   * demo on image / asset build failures
#   * demo for other use cases? Perhaps just use coverband_demo
# * grep strategy or enhancement (on partials, grep for render. partial name and output warnings for anything found)
# * on failed commits with revert record link / data to reason why and try to sort to top hits (IE can't remove any of X pages because of test X, or failure Y)
# * coverband method removal integrated with test for line, would be pretty amazing
# * if script is killed how to safely pick back up where one was (files are easy, harder for the method removal)
#   * perhaps for this we sort by order and allow skipping to last filename worked on, or just skipp a list of files?
#
#####
CIRCLE_TOKEN = ENV['CIRCLE_TOKEN'] || 'XYZ'
PROJECT = ENV['CIRCLE_PROJECT'] || 'coverband_demo'
ORG = ENV['CIRCLE_ORG'] || 'coverband_service'
BRANCH = ENV['CIRCLE_BRANCH'] || 'automated_cleanup'
PROJECT_PATH = ENV['PROJECT_PATH'] || `pwd`
TEST_TARGET = ENV['TEST_TARGET'] || 'bundle exec rspec'
DELETE_TARGET = ENV['DELETE_TARGET'] || "#{PROJECT_PATH}/app/assets/images/**/*"
CIRCLE_JOBS = ENV['CIRCLE_JOBS']

class AutoCleanup
  attr_reader :validator, :strategy

  def initialize
    validator_class = ENV['VALIDATOR'] ? Object.const_get(ENV['VALIDATOR']) : LocalValidator
    strategy_class = ENV['STRATEGY'] ? Object.const_get(ENV['STRATEGY']) : DeletionStrategy
    @validator = validator_class.new(PROJECT_PATH)
    @remote = @validator.is_a?(CircleValidator) || @validator.is_a?(LocalAndCircleValidator)
    @strategy = strategy_class.new(PROJECT_PATH, DELETE_TARGET, @remote)
  end

  def clean
    while strategy.next_run
      if validator.validate
        strategy.success
      else
        strategy.revert
      end
      #ensure the other jobs complete so next capture doesn't recapture this one
      sleep(2) if @remote
    end

    puts 'done'
  end

  def failure
    puts 'failure please see logs'
    exit 1
  end
end

class LocalValidator
  attr_reader :project_dir

  def initialize(target_dir)
    @project_dir = target_dir
  end

  def validate
    status = 1
    Dir.chdir(project_dir) do
      output = `#{TEST_TARGET}`
      status = $?
    end
    status.to_i == 0
  end
end

###
# Uses existing script to run CI and capture response
###
class CircleValidator
  attr_reader :project_dir

  def initialize(target_dir)
    @project_dir = target_dir
  end

  def get_last_commit
    commit_hash = nil
    Dir.chdir(project_dir) do
      commit_hash = `git rev-parse HEAD`.chomp
    end
  end

  def validate
    status = 1
    circle_jobs = ENV['CIRCLE_JOBS'] ? "CIRCLE_JOBS=#{ENV['CIRCLE_JOBS']}" : ''
    cmd = "CIRCLE_TOKEN=#{CIRCLE_TOKEN} #{circle_jobs} CIRCLE_RUNS=1 CIRCLE_BRANCH=#{BRANCH} JOBS_ALL_PASS=true CIRCLE_PROJECT=#{PROJECT} CAPTURE_CURRENTLY_RUNNING=#{get_last_commit} ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/runner.rb"
    puts cmd
    output = `#{cmd}`
    status = $?
    puts "cleaner: circle validation was: #{status}"
    status.to_i == 0
  end
end

# This will fail fast on many errors (with local validator) and never need to run the circle validation, much faster
class LocalAndCircleValidator
  attr_reader :project_validator, :circle_validator

  def initialize(target_dir)
    @project_validator = LocalValidator.new(target_dir)
    @circle_validator = CircleValidator.new(target_dir)
  end

  def validate
    circle_validation = nil
    project_validation = project_validator.validate
    circle_validation = circle_validator.validate if project_validation
    puts "cleaner: validation local #{project_validation} and remote #{circle_validation}"
    project_validation && circle_validation
  end
end

###
# This strategy removes one file at a time. For large files sets this could be slow
###
class DeletionStrategy
  attr_reader :project_dir, :target_folder, :files, :remote

  IGNORE_FILES = [".", ".."]

  def initialize(target_dir, delete_target, remote = false)
    @project_dir = target_dir
    @target_folder = delete_target
    @files = Dir.glob(target_folder).reject{ |file| IGNORE_FILES.include?(file) }
    @remote = remote
  end

  def short_name(file)
    file.gsub(project_dir,'')
  end

  def next_run
    file = files.pop

    puts "cleaner: removing #{file}"
    return unless file
    return next_run if !File.exists?(file) || File.directory?(file)

    Dir.chdir(project_dir) do
      `rm #{file}`
      `git commit -a -m "removed #{short_name(file)}"`
      `git push origin #{BRANCH}` if remote
    end
    file
  end

  def success
    # no op
  end

  def revert
    Dir.chdir(project_dir) do
      commit_hash = `git rev-parse HEAD`
      `git revert --no-edit #{commit_hash}`
    end
  end
end

###
# This strategy removes one file at a time. For large files sets this could be slow
# This should be a more base strategy others call
# note we have rule of threes refactor strategies
###
class FileListStrategy < DeletionStrategy
  attr_reader :project_dir, :files, :remote

  def initialize(target_dir, files, remote = false)
    @project_dir = target_dir
    # normalize all to full file paths
    @files = files.map { |file| file.starts_with?(project_dir) ? file : project_dir + '/' + file }
    @remote = remote
  end
end

###
# This strategy takes the downloaded Coverband view tracker json and automatically attempts removal
###
class CoverbandViewsStrategy < FileListStrategy
  attr_reader :project_dir, :files, :remote

  def initialize(target_dir, views_json_file, remote = false)
    @project_dir = target_dir
    views_data = JSON.parse(File.read(views_json_file))
    # normalize to full file path
    @files = views_data['unused_views'].map { |file| file.starts_with?(project_dir) ? file : project_dir + '/' + file }
    @remote = remote
  end
end

###
# This strategy takes the downloaded Coverband coverage data json and automatically attempts removal of files with 0% runtime coverage
#
# Note:
# * it ignores 0% app/models files that inherit from application record, because these models dynamically run framework code and don't always run any app code
# * TODO: debug eager_loading and merged data seem to contain files that are marked coverband_ignore, fix required in coverband
# (this was fixed in Coverband 4.2.3.rc.2)
###
class CoverbandCoverageFilesStrategy < FileListStrategy
  attr_reader :project_dir, :files, :remote

  def initialize(target_dir, coverage_json_file, remote = false)
    @project_dir = target_dir
    coverage_data = JSON.parse(File.read(coverage_json_file))

    @files = []
    file_names = (coverage_data['merged'].keys - coverage_data['runtime'].keys)
    file_data = coverage_data['runtime']

    # runtime files with 0% runtime hits # NOTE: we might filter this in coverband
    coverage_data['runtime'].each_pair do |file, file_data|
      if file_data['data'] && file_data['data'].select{ |hit| hit.to_i > 0 }.empty?
        file_names << filename
      end
    end

    file_names.each do |file|
      # normalize to full file path
      filename = file.sub('./', (project_dir + '/'))
      # see above todo hack on config
      if File.exists?(filename) && !File.read(filename).match(/ApplicationRecord/) && !filename.match(/config\//)
        @files << filename
      end
    end
    @remote = remote
  end
end

###
# This strategy takes the downloaded Coverband coverage data json and automatically attempts removal of methods with 0% runtime coverage
#
# Note:
# * this is based on code from @blakewest https://github.com/danmayer/coverband/issues/255
# * this won't remove comments above / below a method ;(
###
class CoverbandCoverageMethodsStrategy < DeletionStrategy
  attr_reader :project_dir, :methods_data, :remote

  def initialize(target_dir, coverage_json_file, remote = false)
    @project_dir = target_dir
    coverage_data = JSON.parse(File.read(coverage_json_file))
    compact_methods_data = CoverbandAnalyzer.new(coverage_json_file, project_dir).run!
    @methods_data = []
    compact_methods_data.each do |file_method_data|
      file = file_method_data.shift
      file_method_data.first.each do |method_data|
        @methods_data << [file, method_data]
      end
    end
    @remote = remote
  end

  # delete one method at a time and test
  # using `sed '7,9d' ./file` to remove lines, seems to only soemtimes work, moving to awk
  def next_run
    file_method_data = methods_data.pop

    return unless file_method_data
    file = file_method_data.shift
    # normalize to full file path
    filename = file.sub('./', (project_dir + '/'))
    return next_run if !File.exists?(filename) || File.directory?(filename)

    method_name = file_method_data.first[:method_name]
    starting_line = file_method_data.first[:starting_line]
    ending_line = file_method_data.first[:ending_line]
    Dir.chdir(project_dir) do
      `awk -v m=#{starting_line} -v n=#{ending_line} 'm <= NR && NR <= n {next} {print}' #{filename} > #{project_dir + '/tmp/replace.txt'}; mv #{project_dir + '/tmp/replace.txt'} #{filename}`
      `#{ENV['CLEANUP_PROCESS']}` if ENV['CLEANUP_PROCESS']
      `git commit -a -m "removed #{short_name(filename)} method #{method_name}"`
      `git push origin #{BRANCH}` if remote
    end
    file
  end
end

class CoverbandAnalyzer
  attr_reader :coverband_data, :root_path

  def initialize(coverband_data_filepath, root_path)
    @coverband_data = JSON.parse(File.read(coverband_data_filepath))['merged']
    @root_path = root_path
  end

  def run!
    puts "There are a total of #{coverband_data.keys.length} files to scan"
    data = {
      num_files_covered: coverband_data.keys.length,
      sample_files: coverband_data.keys.sample(5)
    }
    all_data = coverband_data.map do |file_info|
      method_info = find_method_locations(file_info)
      dead_methods = find_dead_methods(method_info, file_info)
      [file_info[0], dead_methods]
    end.select { |item| item[1].length > 0 }

    puts "\n"
    puts "***Total Num Dead Methods In Codebase: #{all_data.sum { |item| item[1].length }} ****"

    sample = all_data.sample
    if sample
      puts "*** SAMPLE ***"
      puts sample[0]
      puts sample[1].join("\n")
    end
    all_data
  end

  def find_dead_methods(method_info, coverband_file_data)
    filepath, data = coverband_file_data
    method_info.each do |this_method|
      this_method[:is_dead] = dead?(this_method, data["data"])
    end
    method_info.select { |item| item[:is_dead] }
  end

  def dead?(method_data, coverage_data)
    return false unless method_data[:starting_index] && method_data[:ending_index]
    method_body_range = (method_data[:starting_index] + 1)...method_data[:ending_index]
    coverage_data[method_body_range] && coverage_data[method_body_range].all? { |num_hits| num_hits == 0 || num_hits.nil? }
  end

  def find_method_locations(coverband_file_data)
    filepath, data = coverband_file_data
    source_filepath = "#{root_path}/#{filepath}"
    method_locations = []

    return method_locations unless File.exist?(source_filepath)

    File.readlines(source_filepath).each_with_index do |line, i|
      indentation_level = line.index(/\S/)
      next unless indentation_level

      method_were_looking_for = method_locations[-1]

      starts_method = true if line[indentation_level..indentation_level+2] == "def"
      ends_method = true if line[indentation_level..indentation_level+2] == "end"

      if starts_method
        method_locations << {
          starting_index: i,
          indentation_level: indentation_level,
          method_name: method_name_from_line(line),
          starting_line: i + 1,
        }
      elsif ends_method && method_were_looking_for && indentation_level == method_were_looking_for[:indentation_level]
        method_were_looking_for[:ending_index] = i
        method_were_looking_for[:ending_line] = i + 1
      end
    end
    method_locations
  end

  def method_name_from_line(line)
    matches = line.match(/\s{0,}def (\w+)/)
    matches && matches[1]
  end
end

###
# This strategy tries to do batches splitting the group in half on each failure
# This will be faster with large sets of files that will be successful on removal...
# It can be much slower if most branches lead to failure scenarios.
#
# This was an interesting idea, but hasn't been that useful in practice
#
###
class BinaryDeletionStrategy
  attr_reader :project_dir, :target_folder, :files, :success_files, :failed_files, :current_files, :remote

  IGNORE_FILES = [".", ".."]

  def initialize(target_dir, delete_target, remote = false)
    @project_dir = target_dir
    @target_folder = delete_target
    @files = Dir.glob(target_folder).reject{ |file| IGNORE_FILES.include?(file) }
    @current_files = files
    @success_files = []
    @failed_files = []
    @remote = remote
  end

  def short_folder_name
    target_folder.gsub(project_dir,'')
  end

  def short_name(file)
    file.gsub(project_dir,'')
  end

  def next_run
    return if files.empty?

    @current_files = files.in_groups(2).to_a[0] if current_files.empty?

    Dir.chdir(project_dir) do
      remove_files(current_files)
      `git commit -a -m "removed from #{short_folder_name} files #{current_files.map{|f| short_name(f) }.join(', ')}"`
      `git push origin #{BRANCH}` if remote
    end
  end

  def success
    @files = files - current_files
    @success_files += current_files
    @current_files = []
  end

  def revert
    Dir.chdir(project_dir) do
      commit_hash = `git rev-parse HEAD`
      `git revert --no-edit #{commit_hash}`
    end

    if current_files.length == 1
      @files = files - current_files
      @failed_files += current_files
      @current_files = []
    else
      @current_files = current_files.in_groups(2).to_a[0]
    end
  end

  private

  def remove_files(files)
    files.each do |file|
      `rm #{target_folder}/#{file}`
    end
  end
end

cleaner = AutoCleanup.new
cleaner.clean
