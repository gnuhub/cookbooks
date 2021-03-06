rightscale_marker :begin


unless File.exists? "/opt/ibm/biginsights/conf/biginsights.properties"

  ## Require libraries 
  
  class Chef::Recipe
    include IMCloudClient
  end
  
  require "rightscale_tools"
  
  
  log "Provider: #{node[:cloud][:provider]}"
  
  
  ## Download Attachments
  
  log "Download Attachments"
  
  IMCloudClient.configure do |config|
    config.api_key = node[:api][:key]
    config.api_url = node[:api][:url]
  end
  
  IMCloudClient.download('/tmp', 'BigInsights Quick Start Edition 2.1 FP1')
    
  
  ## Installing BigInsights Quickstart 2.1 FP1
  
  node[:biginsights][:console][:port] = (node[:biginsights][:console][:use_ssl] == "YES") ? "9443" : "8080"
  
  log "Installing BigInsights Quickstart 2.1 FP1"
  
  log "  Install prerequisites."
  
  case node[:platform]
  when "debian", "ubuntu"
    execute "install-required-packages" do
      command "apt-get install -y libgd2-xpm:i386 libgphoto2-2:i386 ia32-libs-multiarch ia32-libs"
    end
    %w{libstdc++6 lib32stdc++6 libaio1 libpam0g:i386}.each do |pkg|
      package pkg
    end
    
    link "/lib/i386-linux-gnu/libpam.so.0" do
      to "/lib/libpam.so.0"
    end

  else
    %w{expect nc policycoreutils}.each do |pkg|
      package pkg
    end
  end
  
  log "  Set open files limits."
  
  bash "set-ulimits" do
    code <<-EOH
    echo "root hard nofile 16384" >> /etc/security/limits.conf
    echo "root soft nofile 16384" >> /etc/security/limits.conf
    EOH
  end

  log "  Tweak firewall."
  
    restart_iptables_command = "service iptables save"
    if [ "debian", "ubuntu" ].include?( node[:platform] )
      restart_iptables_command = "/usr/sbin/rebuild-iptables"
	end
	
    bash "update firewall" do
      code <<-EOH
        iptables -D FWR -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j REJECT --reject-with icmp-port-unreachable 
        iptables -D FWR -p udp -j REJECT --reject-with icmp-port-unreachable
        iptables -A FWR --protocol tcp --dport #{node[:biginsights][:console][:port]} -j ACCEPT
        iptables -A FWR -s #{node[:cloud][:public_ipv4]} -j ACCEPT
        iptables -A FWR -p tcp -m tcp --tcp-flags SYN,RST,ACK SYN -j REJECT --reject-with icmp-port-unreachable 
        iptables -A FWR -p udp -j REJECT --reject-with icmp-port-unreachable
        echo "-A FWR --protocol tcp --dport #{node[:biginsights][:console][:port]} -j ACCEPT" >> /etc/iptables.d/port_#{node[:biginsights][:console][:port]}_any_tcp
        echo "-A FWR -s #{node[:cloud][:public_ipv4]} -j ACCEPT" >> /etc/iptables.d/port_all_local_tcp
        #{restart_iptables_command}
      EOH
    end
  
  
  if "ec2".eql? node[:cloud][:provider]
    bash "update hosts" do
      code <<-EOH
      echo "127.0.0.1   localhost   localhost.localdomain #{node[:cloud][:public_hostname]}" > /etc/hosts
      EOH
    end
  end
    
  log "  Create directories."
  
  bash "create-directories" do
    code <<-EOH
    mkdir /mnt/hadoop
    ln -s /mnt/hadoop /hadoop
    
    if [ -d "/var/ibm" ]; then
      mv /var/ibm /mnt/ibm
    else
      mkdir /mnt/ibm
    fi
    
    ln -s /mnt/ibm /var/ibm
    EOH
  end
  
  if "ec2".eql? node[:cloud][:provider]
       bash "dir test" do
         code <<-EOH
         rm /hadoop
         rm /var/ibm
         mkdir -p /mnt/ephemeral/opt/ibm
         mkdir -p /mnt/ephemeral/var/ibm
         mkdir -p /mnt/ephemeral/hadoop
         ln -s /mnt/ephemeral/var/ibm /var/ibm
         ln -s /mnt/ephemeral/opt/ibm /opt/ibm
         ln -s /mnt/ephemeral/hadoop /hadoop
         EOH
       end
  end
  
  
  log "  Run the BI admin setup script."
    
  cookbook_file "/tmp/setup_biadmin.sh" do
    mode 00777
  end
  
  execute "/tmp/setup_biadmin.sh #{node[:biginsights][:biadmin][:password]}"
  
  log "  Run BI installation script."
  
  execute "extract-biginsights-media" do
    command "tar --index-file /tmp/biginsights.tar.log -xvvf /tmp/biginsights-quickstart-linux64_*.tar.gz -C /mnt/"
    action :nothing
  end
    
  bash "install-biginsights" do
    code <<-EOH
    ulimit -n 16384
    /mnt/biginsights-quickstart-linux64_*/silent-install/silent-install.sh /tmp/install.xml
    sed -i 's/guardiumproxy,//' /opt/ibm/biginsights/conf/biginsights.properties
    echo 'export PATH=\$PATH:\${PIG_HOME}/bin:\${HIVE_HOME}/bin:\${JAQL_HOME}/bin:\${FLUME_HOME}/bin:\${HBASE_HOME}/bin' >> /home/biadmin/.bashrc 
    EOH
    action :nothing
  end
  
  log "  Configure BigInsights Install Response file - /tmp/install.xml"
  
  hostname = ""
  if "ec2".eql? node[:cloud][:provider]
    hostname = node[:cloud][:public_hostname]
  elsif "softlayer".eql? node[:cloud][:provider]
    hostname = node[:cloud][:public_ipv4]
  else 
    hostname = node[:ipaddress]
  end

  template "/tmp/install.xml" do
    source "install.xml.erb"
    variables(
      :biadmin_password => node[:biginsights][:biadmin][:password],
      :bi_directory_prefix => node[:biginsights][:bi_directory_prefix],
      :master_hostname => hostname,
      :hadoop_distribution => node[:biginsights][:hadoop_distribution],
      :data_node_unique_hostnames => node[:biginsights][:data_node_unique_hostnames]
    )
    notifies :run, "execute[extract-biginsights-media]", :immediately
    notifies :run, "bash[install-biginsights]", :immediately
  end  
  
  
  log "  Stubs for the JAQL exercises and sample apps."
  
  bash "copy-jaql-excercises" do
    code <<-EOH
    echo "Copy the Jaql Exercises file"
    EOH
  end
  
  bash "setup-sample-data" do
    code <<-EOH
    echo "Setup Sample Data"
    EOH
  end
    
  log "  Sync the Hadoop configuration."
  
  bash "sync-hadoop-config" do
    code <<-EOH
    su - biadmin -c "echo 'y' | /opt/ibm/biginsights/bin/syncconf.sh hadoop force"
    EOH
  end
  
end  
  
rightscale_marker :end
