require 'spec_helper'

describe 'chef_client_updater resource' do
  platform 'ubuntu', '22.04'

  describe 'chef-ice product validation' do
    let(:chef_run) do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater']) do |node|
        node.normal['chef_client_updater']['license_id'] = 'test-license-key'
      end
    end

    context 'when using chef-ice as product_name' do
      it 'raises an error about unsupported product' do
        chef_run.converge('test::chef_ice')
        expect { chef_run }.to raise_error(RuntimeError, /Unsupported product: chef-ice/)
      end
    end

    context 'when using chef as product_name' do
      before do
        # Mock the version check to avoid actual upgrade logic
        allow_any_instance_of(Object).to receive(:update_necessary?).and_return(false)
      end

      it 'does not raise an error' do
        expect { chef_run.converge('test::default') }.not_to raise_error
      end
    end
  end

  describe 'license_id parameter' do
    let(:chef_run) do
      ChefSpec::SoloRunner.new(platform: 'ubuntu', version: '22.04', step_into: ['chef_client_updater'])
    end

    context 'when license_id is provided' do
      before do
        allow_any_instance_of(Object).to receive(:update_necessary?).and_return(false)
        chef_run.node.default['chef_client_updater']['license_id'] = 'test-license-123'
      end

      it 'does not log a warning about missing license_id' do
        expect(Chef::Log).not_to receive(:warn).with(/No license_id specified/)
        chef_run.converge('test::default')
      end
    end

    context 'when license_id is not provided' do
      before do
        allow_any_instance_of(Object).to receive(:update_necessary?).and_return(false)
      end

      it 'logs a warning about missing license_id' do
        expect(Chef::Log).to receive(:warn).with(/No license_id specified/)
        chef_run.converge('test::default')
      end
    end
  end
end
