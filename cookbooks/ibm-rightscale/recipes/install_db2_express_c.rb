rightscale_marker :begin

log "Setting up DB2 Download"

directory "/var/imcloud" do
  action :create
end

template "/var/imcloud/imcloud_client.yml" do
  source "imcloud_client.yml.erb"
  user :root
end

log "Installing DB2 Express-C 10.5"

case node[:platform]
when "debian", "ubuntu"
  package "libgphoto2-2:i386"
  package "libgd2-xpm:i386"
  package "libgphoto2-2:i386"
  package "ia32-libs-multiarch"
  package "ia32-libs"
  %w{unzip libstdc++6 lib32stdc++6 libaio1 ia32-libs libpam0g:i386}.each do |pkg|
    package pkg
  end
  
  link "/lib/i386-linux-gnu/libpam.so.0" do
    to "/lib/libpam.so.0"
  end
else
  %w{compat-libstdc++-33 libstdc++-devel dapl dapl-devel libibverbs-devel}.each do |pkg|
    package pkg
  end
  yum_package "pam.i686" do
    version "1.1.1-13.el6"
	action :install
  end
end


if File.exists?("/opt/ibm/db2.lock")
  log "DB2 ALREADY INSTALLED"

  execute "install-db2" do
    command "echo '0 #{`hostname -f`.strip} 0' > /home/#{node[:db2][:instance][:username]}/sqllib/db2nodes.cfg"
    user "root"
	action :run
  end
  
else
  directory node[:db2][:data_path] do
    mode 0755
    action :create
  end
	
  %w{backups log}.each do |dir|
    directory File.join(node[:db2][:data_path], dir) do
      mode 0755
      action :create
    end
  end

  execute "extract-db2-media" do
    command "tar --index-file /tmp/db2exc.tar.log -xvvf /tmp/v10.5_linuxx64_*.tar.gz -C /mnt/"
    user "root"
	action :nothing
  end

  execute "install-db2" do
    command "/mnt/expc/db2setup -r /tmp/db2.rsp"
    user "root"
	action :nothing
  end

  log "  Configure DB2 Install Response file - /tmp/db2.rsp"
  template "/tmp/db2.rsp" do
    source "db2.rsp.erb"
	notifies :run, "execute[extract-db2-media]", :immediately
	notifies :run, "execute[install-db2]", :immediately
  end
  
  file "/tmp/v10.5_linuxx64_*.tar.gz" do
    action :delete
  end
  
  directory File.join(node[:db2][:data_path], "log") do
    mode 2777
  end

  directory node[:db2][:data_path] do
    owner node[:db2][:instance][:username]
	group node[:db2][:instance][:group]
	recursive true
  end
  
  file File.join("/home", node[:db2][:instance][:username], ".bashrc") do
    owner node[:db2][:instance][:username]
    group node[:db2][:instance][:group]
    source ".bashrc"
  end
end


rightscale_marker :end