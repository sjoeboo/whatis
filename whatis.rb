#!/opt/puppet/bin/ruby

require 'optparse'
require 'yaml'
require 'puppet'
require 'puppet/node'
require 'puppet/node/facts'
require 'pp'
require 'json'
require 'yaml'
require 'net/http'
require 'uri'
require 'timeout'
require 'resolv'
require 'ipaddr'

#SETUP
puppetdb_host="puppetdb"
puppetdb_port="8080"
domains=[".mydomain.local",".myotherdomain.something"]
#Array of the basic info we want to return w/o -a

basic_info=["hostname","born_on","manufacturer","productname","serialnumber","operatingsystem","operatingsystemrelease","architecture","processor0","processorcount","memorytotal","kernelrelease","ipaddress","macaddress","virtual","uptime"]

options={}
OptionParser.new do |opts|
        opts.banner = "Usage: whatis [options] <hostname>"

        opts.on("-j","--json","JSON output") do |j|
                options[:json] = j
        end
        opts.on("-y","--yaml","YAML output") do |y|
                options[:yaml] = y
        end
        opts.on("-p","--pp","Pretty Print output") do |p|
                options[:pp] = p
        end
        opts.on("-a","--all","Use all facts") do |a|
                options[:all] = a
        end
end.parse!

if ARGV.length != 1
        puts "Please pass a hostname, see --help"
        exit
else
        #see if we were given an ip instead, and if so, get hostname
        if !(IPAddr.new(ARGV[0]) rescue nil).nil?
                #got an ip, convert
                host = Resolv.new.getname ARGV[0]
        else 
          host = ARGV[0].downcase
        end
end

#if we passed shortname, get fqdn
def domain_fix(host,domain,match)
#Fix domain if needed
      if host.match(match)
          fqdn = host.to_s
      else
          fqdn = host.to_s + domain
      end
      return(fqdn)
end

def get_facts(puppetdb_host,puppetdb_port,fqdn)
  uri=URI.parse("http://#{puppetdb_host}:#{puppetdb_port}/v2/nodes/#{fqdn}/facts")
  response = Net::HTTP.get_response(uri)
  facts=JSON.parse(response.body)
  return(facts)
end

def facts_to_hash(facts)
  #Parse the fact output from puppetdb into a simpler hash
  node_facts=Hash.new
  facts.each do |fact|
    node_facts[fact["name"]] = fact["value"]
  end
  return node_facts
end

#do output
def output(options,values,facts2)
  #output time
  if options[:json] == true
          puts facts2.to_json
  elsif options[:yaml] == true
          puts facts2.to_yaml
  elsif options[:pp] == true
          pp facts2
  else
    if options[:all] == true
        pp facts2
    else
        values.each do |val|
          puts "#{val.capitalize}: #{facts2[val]}"
        end
    end
  end
end

#MAIN
#try the name as given first, some hosts have short certnames(sigh)
puts "Searching for #{host}..."
$facts=get_facts(puppetdb_host,puppetdb_port,host)
if $facts == []
  domains.each do |dom|
    match=dom.split('.')[-1]
    fqdn=domain_fix(host,dom,match)
    $facts=get_facts(puppetdb_host,puppetdb_port,fqdn)
    if $facts != []
      #we got data, break
      break
    else
      next
    end
  end
end

if $facts == []
#if we still have no info, exit
  puts "Unable to find #{host}, please check the name"
  exit
end

node_facts=facts_to_hash($facts)

facts2 = Hash.new
if options[:all] == true
  facts2 = node_facts
else
  #Example of detecting a fact and adding it to the base output list
  if node_facts['compute_node'] == 'true'
        basic_info.push('compute_node')
        basic_info.push('compute_type')
  end
  basic_info.each do |val|
    facts2[val] = node_facts[val]
  end
end

output(options,basic_info,facts2)
