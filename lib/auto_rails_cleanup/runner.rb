require 'byebug'
require 'json'
require 'time'
require 'active_support/all'

#####
# This script uses documented CircleCI public APIs get a token from CircleCI and set in your ENV
#
# This script will run a project and banch X number of times and calculate it's success / failure rate.
# Inititally developed to calculate success rate of flaky test suites, but also used to verify automated commits
#
# execute:
# CIRCLE_TOKEN=YOUR_TOKEN ruby ruby ../auto_rails_cleanup/lib/auto_rails_cleanup/runner.rb
#
# How to use...
#
# 1. branch from master
# 2. run this script to capture current baseline
# 3. look at the failures that caused less than 100% success
# 4. use the single test runner and other methods to fix the flaky tests
# 5. check in and push fixes to the branch and run this script again...
# 6. repeat until you acheive your desired success rate.
###
CIRCLE_TOKEN = ENV['CIRCLE_TOKEN'] || 'XYZ'
PROJECT = ENV['CIRCLE_PROJECT'] || 'coverband_demo'
ORG = ENV['CIRCLE_ORG'] || 'coverband_service'
BRANCH = ENV['CIRCLE_BRANCH'] || 'auto_clean'
RUNS = (ENV['CIRCLE_RUNS'] || 20).to_i
# failure rate is calculated for first job, other jobs used to ensure full workflow completes
JOBS = (ENV['CIRCLE_JOBS'] || 'test').split(',') #test this for spectre
JOBS_ALL_PASS = ENV['JOBS_ALL_PASS'] || false

class CircleStats

  def initialize
    @stats = []
    @times = []
    @last_built_at = nil
  end

  def run_build
    @last_built_at = Time.now.utc.to_i
    cmd = "curl -X POST --header 'Content-Type: application/json' -d '{\"branch\": \"#{BRANCH}\" }'  'https://circleci.com/api/v1.1/project/github/#{ORG}/#{PROJECT}/build?circle-token=#{CIRCLE_TOKEN}'"
    # puts cmd
    if ENV['CAPTURE_CURRENTLY_RUNNING']
      # ensure the build has started, TODO remove sleep
      sleep(10)
    else
      puts `#{cmd}`
    end
  end

  ###
  # capture build targetting specific commit to avoid capturing previous build results
  ###
  def capture_build
    # limit is current HB total workflow
    #TODO dont need increased limit
    cmd =  if ENV['CAPTURE_CURRENTLY_RUNNING']
      "curl 'https://circleci.com/api/v1.1/project/github/#{ORG}/#{PROJECT}/tree/#{BRANCH}?circle-token=#{CIRCLE_TOKEN}&limit=20'"
    else
      "curl 'https://circleci.com/api/v1.1/project/github/#{ORG}/#{PROJECT}/tree/#{BRANCH}?circle-token=#{CIRCLE_TOKEN}&limit=9'"
    end
    puts cmd
    data = `#{cmd}`
    data = JSON.parse(data)
    if ENV['CAPTURE_CURRENTLY_RUNNING']
      # ignore all builds that aren't the current git sha
      data.reject!{ |i| (i['all_commit_details'].first==nil || !i['all_commit_details'].last['commit'].starts_with?(ENV['CAPTURE_CURRENTLY_RUNNING'])) }
    else
      data.reject!{ |i| i['start_time'].nil? || Time.iso8601(i['start_time']).to_i < (@last_built_at + 10) }
    end

    tests_jobs = data.select{ |job| JOBS.include?(job['workflows']['job_name']) }
    metric_job = data.select{ |job| job['workflows']['job_name']==JOBS.first }.first
    raise "one of the jobs isn't running yet" unless tests_jobs.length == JOBS.length
    tests_jobs.each do |job|
       raise "still running #{job}" unless (job['outcome']=='success' || job['outcome']=='failed')
    end

    outcome = if JOBS_ALL_PASS
                tests_jobs.select { |job| job['outcome']=='success' }.length == JOBS.length ? 'success' : 'failed'
              else
                metric_job['outcome']
              end

    puts "recording: #{outcome}"
    @stats << outcome
    @times << Time.iso8601(metric_job['stop_time']) - Time.iso8601(metric_job['start_time'])
  rescue => err
    puts "waiting, #{err}"
    sleep(15)
    retry
  end

  def run_builds
    RUNS.times do |i|
      run_build
      sleep(10) # let it get started
      capture_build
      sleep(45) # hack as other jobs sometimes lag, like pacts
      break if failed_max?
    end
  end

  def failed_max?
    @stats.select{ |s| s=='failed'}.length >= 2
  end

  def total_failure?
    @stats.select{ |s| s=='failed'}.length == @stats.length
  end

  def average_time
    @times.sum / @times.size
  end

  def median_time
    tmp = @times.sort
    mid = (tmp.size / 2).to_i
    tmp[mid]
  end

  def calc_stats
    puts @stats.join(', ')
    fail_rate = if failed_max?
                  'failed twice, > 10% failure rate'
                elsif  total_failure?
                  'total failure, 100% failure rate, broken'
                else
                  (@stats.select{ |s| s=='failed' }.length.to_f) / @stats.length.to_f
                end
    puts "fail rate: #{fail_rate}"

    puts ""
    puts "build times (sec):"
    puts "average:\t#{average_time}"
    puts "median:\t#{median_time}"
    puts "times: #{@times.map(&:to_s).join(',')}"
    # non-zero exit status if not a 100% success rate
    exit 1 unless @stats.select{ |s| s=='failed' }.length == 0
  end
end

stats = CircleStats.new
stats.run_builds
stats.calc_stats
