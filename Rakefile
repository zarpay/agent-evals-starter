# frozen_string_literal: true

require 'pathname'
require 'rspec/core/rake_task'
require_relative 'lib/acme'

RSpec::Core::RakeTask.new(:spec)
task default: :spec

namespace :db do
  desc 'Delete the Acme database; the next connect creates and seeds it again'
  task :reset do
    FileUtils.rm_f(Dir[File.join(Acme::ROOT, 'db', '*.sqlite3*')])
  end
end

# Every eval reads the same variables:
#   MODEL    an OpenRouter model id      default: production's (Acme::Inference::DEFAULT_MODEL)
#   SAMPLES  answers per case            default: 3
#   THREADS  answers in parallel         default: 4, under the database pool
#   CASES    comma-separated case ids    default: all
def eval_options(cases)
  wanted = ENV.fetch('CASES', '').split(',').map(&:strip)
  unknown = wanted - cases.map(&:id)
  abort "No case is called #{unknown.join(', ')}." if unknown.any?

  { cases: wanted.empty? ? cases : cases.select { wanted.include?(_1.id) },
    model: ENV.fetch('MODEL', Acme::Inference::DEFAULT_MODEL),
    samples: Integer(ENV.fetch('SAMPLES', '3')),
    threads: Integer(ENV.fetch('THREADS', '4')) }
end

def run_eval(suite)
  options = eval_options(suite::Case.all)
  answers = suite::Run.new(**options.slice(:model, :samples, :threads)).call(options[:cases])
  report = suite::Report.new(answers, **options.slice(:model, :samples))
  puts "#{report.summary} · #{Pathname(report.write).relative_path_from(Acme::ROOT)}"
end

namespace :evals do
  desc 'Measure the support agent: right tools, right actions, few turns'
  task :support do
    require_relative 'evals/support/case'
    require_relative 'evals/support/run'
    require_relative 'evals/support/report'
    Acme::Database.connect
    run_eval(Evals::Support)
  end

  desc 'Measure the tagger, a single call with no tools (the warm-up)'
  task :tagging do
    require_relative 'evals/tagging/case'
    require_relative 'evals/tagging/run'
    require_relative 'evals/tagging/report'
    run_eval(Evals::Tagging)
  end
end
