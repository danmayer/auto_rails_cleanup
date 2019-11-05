require 'byebug'
require 'json'
require 'time'
require 'active_support/all'

#####
# This script runs to collapse all the merge and revert commits back to back after running the cleaner script.
#
# Usage: run from project directory on branch you wish to clean. `ruby ../korefak_utils/circle_stats/git_cleaner.rb`
#
# TODO: this can get the wrong target on the coverband_method_cleaning strategy
#
# Why?:
#
# * while the style of commit / revert for the original author can be very helpful (debug issues where they hoped to be able to remove more than they could)
# * it can be very verbose and hard to review the PR
#     * github gets upset with hundreds of commits in a PR (and can't display a good diff)
#     * it is less obvious to the PR reviewer what exactly was removed
#     * the commit history isn't really useful for anyone in the future, so it is good to collapse the word which didn't succeed
###
class GitCleanup
  attr_reader :validator, :strategy
  
  def initialize
  end

  def clean
    commits = `git log origin/master..HEAD`

    previous_hash = nil
    previous_target = nil
    commits.each_line do |commit|
      puts commit
      hash = commit.split(' ').first
      target = commit.split(' ').last.gsub('"','')
      revert = !!commit.match(/Revert/)
      if revert
        previous_hash = hash
        previous_target = target
      else
        if previous_target == target
          `git rebase -p --onto #{previous_hash}\^ #{previous_hash}`
          `git rebase -p --onto #{hash}\^ #{hash}`
        end
        previous_hash = nil
        previous_target = nil
      end
    end
    puts 'done'
  end
end


cleaner = GitCleanup.new
cleaner.clean
