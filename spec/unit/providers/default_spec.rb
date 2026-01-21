require 'spec_helper'

describe 'chef_client_updater provider' do
  platform 'ubuntu', '22.04'

  let(:chef_run) do
    ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
      node.normal['chef_client_updater']['product_name'] = product_name
      node.normal['chef_client_updater']['version'] = '18.0.0'
      node.normal['chef_client_updater']['license_id'] = 'test-license-key'
    end
  end

  context 'when product_name is chef-ice' do
    let(:product_name) { 'chef-ice' }

    it 'raises an error about unsupported product' do
      chef_run.converge('chef_client_updater::default')
      expect { chef_run }.to raise_error(RuntimeError, /Unsupported product: chef-ice/)
    end

    it 'includes error message stating cookbook only supports Chef 18 and below' do
      chef_run.converge('chef_client_updater::default')
      expect { chef_run }.to raise_error(RuntimeError, /only supports omnibus versions of Chef Infra Client 18 and below/)
    end
  end

  context 'when product_name is chef' do
    let(:product_name) { 'chef' }

    before do
      # Mock the version check to avoid actual upgrade logic
      allow_any_instance_of(Object).to receive(:update_necessary?).and_return(false)
    end

    it 'does not raise an error' do
      expect { chef_run.converge('chef_client_updater::default') }.not_to raise_error
    end
  end

  context 'when product_name is not set (defaults to chef)' do
    let(:product_name) { nil }

    before do
      # Mock the version check to avoid actual upgrade logic
      allow_any_instance_of(Object).to receive(:update_necessary?).and_return(false)
    end

    it 'does not raise an error' do
      expect { chef_run.converge('chef_client_updater::default') }.not_to raise_error
    end
  end
end
