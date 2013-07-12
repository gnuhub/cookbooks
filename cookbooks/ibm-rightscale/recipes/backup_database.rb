rightscale_marker :begin

log "Backup DB2 Database"


log "Running Database Backup"

execute_as_user "create-database" do
  command "db2 backup DB #{node[:db2][:database][:name]} #{node[:db2][:database][:options]}"
  user node[:db2][:instance][:username]
  action :run
end

if node[:backup][:save_to_cloud] == "yes"
  log "Saving Backup to cloud"

  rightscale_tools_gem = `ls /var/cache/rightscale/cookbooks/default/*/cookbooks/rightscale/files/default/rightscale_tools-*.gem`.strip
  
  gem_package "rightscale_tools" do
    source rightscale_tools_gem
    action :install
  end
  
  require "rightscale_tools"
  
  users_home_dir = File.join("/home", node[:db2][:instance][:username])
  #backup_files = Dir.entries(users_home_dir).select { |file| file.include?(node[:db2][:database][:name]) }
  #newest = backup_files.max { |a,b| (File.mtime(File.join(dir,a)) <=> File.mtime(File.join(dir,b))) }
  newest = `ls #{users_home_dir} | grep #{node[:db2][:database][:name]} | sort | tail -1`
  
  log "users_home_dir: #{users_home_dir.inspect}"
  #log "backup_files: #{backup_files.inspect}"
  log "newest: #{newest.inspect}"
  
  @ros = RightScale::Tools::ROS.factory(node[:backup][:cloud][:name], node[:backup][:cloud][:key], node[:backup][:cloud][:secret])

  @ros.put_object_from_file node[:backup][:bucket], File.join(node[:backup][:path], newest), File.join(users_home_dir, newest)
end

rightscale_marker :end