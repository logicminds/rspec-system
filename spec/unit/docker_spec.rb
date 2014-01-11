require 'spec_helper'
require 'rspec-system/node_set/docker'

describe RSpecSystem::NodeSet::Docker do

  let(:setname) { 'set name' }
  let(:custom_prefabs_path) { '' }
  let(:config) do
    {
      'nodes' => {
        'container1.example.com' => { 'prefab' => 'ubuntu-1210-docker' },
        'container2.example.com' => { 'prefab' => 'ubuntu-1210-docker' }
      }
    }
  end
  let(:options) { { :destroy => true } }

  #let(:value) { :id => id, :name => name }
  #let(:image) { 'base' }
  let(:env_vars) do
    {
      'RS_DESTROY'     => true,
    }
  end

  let(:rs_storage) do
    { }
  end

  let(:log) do
    log = stub :log
    log.stubs :info
    log
  end
  subject { described_class.new(setname, config, custom_prefabs_path, options) }

  before :each do

    env_vars.each { |k,v| ENV[k] = v.to_s }
    RSpec.configuration.stubs(:rs_storage).returns rs_storage
    described_class.any_instance.stubs(:log).returns log
    subject.stubs(:make_unique_name).returns('rspec-system-container1.example.com-12345678')
    subject.stubs(:image_exists?).returns(true)
    subject.stubs(:pull_image).returns(true)
    subject.stubs(:build_image).returns(true)
    subject.stubs(:rm_container).returns(true)
    subject.stubs(:kill_container).returns(true)
    subject.stubs(:container_name).returns('abc123abc123')
    subject.stubs(:mapped_port).returns('2222')
    @session = mock()
    @session.stubs(:closed?).returns(true)
    @session.stubs(:close).returns(true)
    subject.stubs(:ssh_connect).with(:host => '127.0.0.1', :user => 'root', :net_ssh_options => {
      :password => 'rspec',
      :port     => '2222' }).returns(@session)

  end

  it 'should have the PROVIDER_TYPE docker' do
    expect(described_class::PROVIDER_TYPE).to eq 'docker'
  end

  #it 'should read image from the nodeset' do
  #  puts subject.inspect
  #  expect(subject[:node_timeout]).to eq node_timeout
  #end
  #
  describe '#launch' do
    it 'should return a valid object' do

      subject.launch.should be_nil
      rs_storage[:nodes].should eq({
        "container1.example.com"=>{:id=>"abc123abc123",:name=>"rspec-system-container1.example.com-12345678"},
        "container2.example.com"=>{:id=>"abc123abc123",:name=>"rspec-system-container1.example.com-12345678"}
                                   })
    end
  end

  describe '#connect' do

    it 'should return a valid ssh object' do

      subject.launch
      subject.connect.should be_nil
      container = rs_storage[:nodes]['container1.example.com'][:id]
      container.should eq("abc123abc123")
      ssh = rs_storage[:nodes]['container1.example.com'][:ssh]
      ssh.should eq(@session)
    end
  end


  describe '#teardown with destroy' do

    it 'should remove all containers' do

      subject.launch
      subject.connect
      subject.expects(:kill_container).once.with('container1.example.com', 'abc123abc123')
      subject.expects(:rm_container).once.with('container2.example.com', 'abc123abc123')
      subject.teardown
    end

  # need to move the creation of the object to a different describe block
  describe '#teardown without destroy'

    xit 'should not remove any containers' do

      subject.launch
      subject.connect
      subject.expects(:kill_container).times(0).with('container1.example.com', 'abc123abc123')
      subject.expects(:rm_container).times(0).with('container2.example.com', 'abc123abc123')
      subject.teardown
    end

  end

  describe '#run' do

    xit 'should be able to run a command as vagrant user' do
      subject.launch
      subject.connect
      cmd = "cd /tmp && sudo sh -c docker list)"
      subject.expects(:ssh_exec!).times(1).with(cmd)
      subject.run(:n =>'docker list', :n => 'container1.example.com')
    end
  end

end

