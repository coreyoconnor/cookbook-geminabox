include_recipe 'nginx'

%w(000-default default).each do |site|
  nginx_site site do
    enable false
  end
end

if(node[:geminabox][:ssl][:enabled])
  if(node[:geminabox][:ssl][:key].nil? && node[:geminabox][:ssl][:snakeoil])

    package 'ssl-cert'

    group 'ssl-cert' do
      action :modify
      members node[:geminabox][:www_user]
      append true
    end
    node.set[:geminabox][:ssl][:key_file] = '/etc/ssl/private/ssl-cert-snakeoil.key'
    node.set[:geminabox][:ssl][:cert_file] = '/etc/ssl/certs/ssl-cert-snakeoil.pem'
  else
    geminabox_key = node[:geminabox][:ssl][:key]
    geminabox_cert = node[:geminabox][:ssl][:cert]
  end
end

if(geminabox_key && geminabox_cert)
  {:key => geminabox_key, :cert => geminabox_cert}.each_pair do |key,val|
    file File.join(node[:nginx][:dir], "geminabox.ssl.#{key}") do
      content val
    end
    node.set[:geminabox][:ssl]["#{key}_file"] = File.join(node[:nginx][:dir], "geminabox.ssl.#{key}")
  end
end

if(node[:geminabox][:auth_required])
  if(node[:geminabox][:auth_required].is_a?(String))
    if(File.exists?(node[:geminabox][:auth_required]))
      htpasswd_file = node[:geminabox][:auth_required]
    else
      file File.join(node[:nginx][:dir], 'geminabox.htpasswd') do
        content node[:geminabox][:auth_required]
      end
      geminabox_auth = File.join(node[:nginx][:dir], 'geminabox.htpasswd')
    end
  elsif(node[:geminabox][:auth_required].is_a?(Hash)) # generate file
    require 'webrick/httpauth'
    require 'tempfile'
    tmp = Tempfile.new('geminabox')
    begin
      htpasswd = WEBrick::HTTPAuth::Htpasswd.new(tmp.path)
      node[:geminabox][:auth_required].each do |user, pass|
        htpasswd.set_passwd 'geminabox', user, pass
      end
      htpasswd.flush
      htpasswd_contents = File.read(tmp.path)
      file File.join(node[:nginx][:dir], 'geminabox.htpasswd') do
        content htpasswd_contents
      end
      geminabox_auth = File.join(node[:nginx][:dir], 'geminabox.htpasswd')
    ensure
      tmp.close
      tmp.unlink
    end
  else
    raise "Unknown authentication setting provided for geminabox configuration"
  end
end

template File.join('/', 'etc', 'nginx', 'sites-available', 'geminabox') do
  source 'nginx-geminabox.erb'
  variables(
    :socket => File.join(node[:geminabox][:base_directory], 'unicorn.socket'),
    :root => node[:geminabox][:base_directory],
    :ssl => node[:geminabox][:ssl][:enabled],
    :ssl_cert => node[:geminabox][:ssl][:cert_file],
    :ssl_key => node[:geminabox][:ssl][:key_file],
    :auth_file => geminabox_auth
  )
  mode '0644'
  notifies :restart, 'service[nginx]'
end

nginx_site 'default' do
  enable false
  notifies :restart, 'service[nginx]'
end

nginx_site 'geminabox' do
  enable true
  notifies :restart, 'service[nginx]'
end
