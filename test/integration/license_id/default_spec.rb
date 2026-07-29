# The license-id suite uses the Trial API which only supports 'latest', so we cannot
# assert a specific pinned version. Instead we verify that the chef-client was upgraded
# beyond the kitchen baseline (18.6.2) and that the embedded gem meets the minimum.
describe command('chef-client -v') do
  its('stdout') { should match '^Chef Infra Client: ' }
  its('stdout') { should_not match '^Chef Infra Client: 18\.6\.2' }
end

describe command('/opt/chef/embedded/bin/gem -v') do
  its('stdout') { should cmp >= '2.6.11' }
end
