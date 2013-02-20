#
# Cookbook Name:: storm
# Recipe:: default
#
# Copyright 2012, Webtrends, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

include_recipe "runit"
include_recipe "java"

#include_recipe "build-essential"
#include_recipe "zeromq"
#include_recipe "jzmq"

if ENV["deploy_build"] == "true" then
  log "The deploy_build value is true so un-deploy first"
  include_recipe "storm::undeploy-default"
end

# install dependency packages
%w{unzip python libzmq1 }.each do |pkg|
  package pkg do
    action :install
  end
end

# search
Chef::Log.debug("Nimbus nodes")
Chef::Log.debug(node[:opsworks][:layers]['storm-nimbus'][:instances])
storm_nimbus = node[:opsworks][:layers]['storm-nimbus'][:instances].first
Chef::Log.debug("Storm Nimbus")
Chef::Log.debug(storm_nimbus)

# search for zookeeper servers
zookeeper_quorum = Array.new
#search(:node, "role:zookeeper AND chef_environment:#{node.chef_environment}").each do |n|
#	zookeeper_quorum << n[:fqdn]
#end

Chef::Log.debug("Zookeeper instances:")
Chef::Log.debug(node[:opsworks][:layers]['zookeeper'][:instances])

node[:opsworks][:layers]['zookeeper'][:instances].each do |k,v|
  Chef::Log.debug(v)
  Chef::Log.debug(v[:public_dns_name])
  zookeeper_quorum << v[:public_dns_name]
end

Chef::Log.debug(zookeeper_quorum)

install_dir = "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"

# setup storm group
group "storm" do
end

# setup storm user
user "storm" do
  comment "Storm user"
  gid "storm"
  shell "/bin/bash"
  home "/home/storm"
  supports :manage_home => true
end

# setup directories
%w{install_dir local_dir log_dir}.each do |name|
  directory node['storm'][name] do
    owner "storm"
    group "storm"
    action :create
    recursive true
  end
end

# download storm
remote_file "/tmp/storm-#{node[:storm][:version]}.zip" do
  source "#{node['storm']['download_url']}"
  owner  "storm"
  group  "storm"
  mode   00744
  not_if "test -f /tmp/storm-#{node['storm']['version']}.zip"
end

# uncompress the application tarball into the install directory
execute "unzi[" do
  user    "storm"
  group   "storm"
  creates "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
  cwd     "#{node['storm']['install_dir']}"
  command "unzip /tmp/storm-#{node['storm']['version']}.tar.gz"
end

# create a link from the specific version to a generic current folder
link "#{node['storm']['install_dir']}/current" do
	to "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
end

# storm.yaml
template "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}/conf/storm.yaml" do
  source "storm.yaml.erb"
  mode 00644
  variables(
    :nimbus => storm_nimbus,
    :zookeeper_quorum => zookeeper_quorum
  )
end

# sets up storm users profile
template "/home/storm/.profile" do
  owner  "storm"
  group  "storm"
  source "profile.erb"
  mode   00644
  variables(
    :storm_dir => "#{node['storm']['install_dir']}/storm-#{node['storm']['version']}"
  )
end

template "#{install_dir}/bin/killstorm" do
  source  "killstorm.erb"
  owner "root"
  group "root"
  mode  00755
  variables({
    :log_dir => node['storm']['log_dir']
  })
end
