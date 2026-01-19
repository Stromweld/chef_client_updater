chef_client_updater "Install Chef latest via trial api" do
  channel 'stable'
  version 'latest'
  post_install_action 'exec'
  install_timeout 599
  license_id node['chef_client_updater']['license_id'] if node['chef_client_updater']['license_id']
end
