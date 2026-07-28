require 'rake'

# Run Ruby unit tests via Chef Workstation's bundled RSpec.
# Mirrors the 'unit' job in .github/workflows/lint.yml.
desc 'Run Ruby unit tests (spec/)'
task 'spec:unit' do
  sh({ 'CHEF_LICENSE' => 'accept-no-persist' }, 'chef exec rspec spec/ --format documentation')
end

# Run Pester tests for Windows-specific PowerShell behaviour.
# These tests verify the $LASTEXITCODE guard logic in execute_install_script
# (providers/default.rb) which cannot be exercised from RSpec/ChefSpec.
#
# Requires:  Windows + Pester v5 (built into Windows 10+)
# Update:    Install-Module -Name Pester -Force -SkipPublisherCheck
desc 'Run Windows Pester tests (spec/windows/)'
task 'spec:windows' do
  unless Gem.win_platform?
    puts 'spec:windows skipped — Pester tests only run on Windows'
    next
  end
  sh 'powershell -NonInteractive -Command "Invoke-Pester spec/windows/ -Output Detailed; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }"'
end

desc 'Run all tests (spec:unit + spec:windows on Windows, spec:unit only on non-Windows)'
task spec: Gem.win_platform? ? %w(spec:unit spec:windows) : %w(spec:unit)

task default: :spec
