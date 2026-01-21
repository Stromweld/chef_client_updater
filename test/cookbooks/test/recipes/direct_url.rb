raise 'This test is only for RHEL 6' unless platform_family?('rhel') && node['platform_version'].to_i == 6

chef_client_updater 'Install latest Chef' do
  version '18.9.4'
  download_url_override 'https://packages.chef.io/files/stable/chef/18.9.4/el/9/chef-18.9.4-1.el9.x86_64.rpm'
  post_install_action 'exec'
end
