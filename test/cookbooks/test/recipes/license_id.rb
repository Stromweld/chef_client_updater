chef_client_updater "Install Chef #{node['chef_client_updater']['version']}" do
  channel 'stable'
  version node['chef_client_updater']['version']
  # post_install_action 'exec'
  install_timeout 599
  license_id node['chef_client_updater']['license_id'] if node['chef_client_updater']['license_id']
end
