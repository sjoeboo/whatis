#!/usr/bin/ruby

require 'optparse'
require 'yaml'
require 'puppet'
require 'puppet/node'
require 'puppet/node/facts'
require 'pp'
require 'json'
require 'yaml'
require 'xmlrpc/client'
require 'net/http'
require 'timeout'

#Setup
#
#List of values we want, unelss we call w/ --all
values = ["hostname","born_on","notes","owner","group","docs","rt","manufacturer","productname","serialnumber","operatingsystem","operatingsystemrelease","architecture","processor0","processorcount","memorytotal","kernelrelease","ipaddress","macaddress","vlan","location_row","location_rack","location_ru","uptime","virtual"]

#Puppet Server Info:
puppet_server="puppet.your.domain.com"
puppet_port="8140"
puppet_url="https://" + puppet_server + ":" + puppet_port
cobbler_url="http://cobbler.you.domain.com/cobbler_api"
domain=".you.domain.com" #domain to append to hostnames if needed

match=domain.split('.')[-1]


#Deal w/ options
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
        host = ARGV[0]
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

#get facts
def get_facts(fqdn,puppet_url)
  fact_url = puppet_url + "/production/facts/" + fqdn
  fact_cmd = "curl -s -k -H \"Accept: yaml\" " + fact_url
  rawfacts = `#{fact_cmd}`
  return(rawfacts)
end

#if its a hypervisor, get additional facts
def is_hypervisor(facts,facts2,values)
#See if we are dealing w/ a hypervisors here:
if facts["kvm_production"] == "true"
        #Get last reported list of VMS running on this host
        facts2["hypervisor"] = "true"
        facts2["vms"] = facts["kvm_vms"]
        values.push("hypervisor")
        values.push("vms")
end

end

#if its virtual, get additional facts
def is_virtual(facts2,values,puppet_url)
#Lets see if it is virtual so we can add a fact about where it is running...
if facts2["virtual"] == "kvm"
        hypervisor_url = puppet_url + "/production/facts_search/search?facts.kvm_production=true"
        hypervisor_cmd = "curl -s -k -H 'Accept: YAML' " +  hypervisor_url
        hypervisor_yaml = `#{hypervisor_cmd}`
        hypervisors = YAML::load(hypervisor_yaml)
	hypervisors.each do |hyp|
                hyp_facts_url = puppet_url + "/production/facts/" + hyp
                hyp_facts_cmd = "curl -s -k -H \"Accept: yaml\" " + hyp_facts_url
                hyp_facts = `#{hyp_facts_cmd}`
                hyp_facts = hyp_facts.sub("!ruby/object:Puppet::Node::Facts","")
                hyp_facts = YAML::parse(hyp_facts)
                hyp_facts = hyp_facts.transform
		vms = eval(hyp_facts["values"]["kvm_vms"])
                vms.each do |vm|
                        if vm.match(facts2["hostname"])
                                facts2["hypervisor"] = "#{hyp}"
                        end
                end
        end
        #Add "hypervisor" to the list of values we care about
        values.push("hypervisor")
end
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

#check for cname, returns new fdqn
def cname_check(host)
  host_lookup="host -t CNAME #{host}"
  host_out=`#{host_lookup}`
  if host_out.match("alias")
          new_host=host_out.split[-1].chomp(".")
          fqdn=new_host
          return(fqdn)
  elsif host_out.match("NXDOMAIN")
	puts "Could not locate CNAME, system is unknown"
	exit
    end
end

#get cobbler info directly, returns cobbler_info hash
def cobbler_direct(cobbler_url,fqdn)
  connection = XMLRPC::Client.new2(cobbler_url)
  system_data = connection.call("find_system_by_dns_name","#{fqdn}")
  cobbler_info=Hash.new
  if !system_data.empty? #found it in cobbler
          #We need to get some minimal data from cobbler
          cobbler_macaddress = system_data["mac_address_eth0"]
          cobbler_ipaddress = system_data["ip_address_eth0"]
          cobbler_comment = system_data["comment"]
          comment = YAML::load(cobbler_comment)
          cobbler_info["hostname"] = system_data["hostname"]
          cobbler_info["ipaddress"] = cobbler_ipaddress
          cobbler_info["macaddress"] = cobbler_macaddress
          cobbler_info["owner"] = comment["owner"]
          cobbler_info["group"] = comment["group"]
          cobbler_info["rt"] = comment["rt"]
          cobbler_info["docs"] = comment["docs"]
          cobbler_info["notes"] = comment["notes"]
        end
        return (cobbler_info)
end

#try to hit rackfacts direct, return rack_info hash
def racktables_direct(fqdn)
  rackfact_host = "racktables"
  #need shortname...
  hostname=fqdn.split('.')[0]
  rackfact_dir  = "/rackfacts/systems/#{hostname}"
  rack_info=Hash.new
  begin
  Timeout::timeout(2) {
          rescode=Net::HTTP.get_response rackfact_host,rackfact_dir
          if (rescode.code =~ /2|3\d{2}/ )
          rackfact = YAML::load(rescode.body)
          rack_info["location_ru"] = rackfact["ru"]
          rack_info["location_rack"] = rackfact["rack"]
          rack_info["location_row"] = rackfact["row"]
          end
          }
  rescue Timeout::Error
  end
  return rack_info
end


#"MAIN" if you will...
fqdn=domain_fix(host,domain,match)
rawfacts = get_facts(fqdn,puppet_url)
if rawfacts.match("Could")
        puts "Unable to find #{host}, checking for CNAME.."
        #We couldn't find it...lets try dns lookups..?
        #lookup hostname(short, first), see if its a cname
        fqdn=cname_check(host)
        rawfacts = get_facts(fqdn,puppet_url)
        #try again...
        if rawfacts.match("Could")
                #Still couldn't find it. try cobbler and racktables individually for any info we can find...
                puts "unable to locate in puppet. Attempting to get info from Cobbler..."
                puppet_fail=true
                cobbler_info=cobbler_direct(cobbler_url,fqdn)
                rack_info=racktables_direct(fqdn)
                combo_info=cobbler_info.merge(rack_info)
        end
end

if puppet_fail != true
        rawfacts = rawfacts.sub("!ruby/object:Puppet::Node::Facts","")
        rawfacts = YAML::parse(rawfacts)
        rawfacts = rawfacts.transform

        #We can now access things like:
        # rawfacts["values"]["virtual"]
        facts = Hash.new
        rawfacts["values"].each_pair do |a,b|
                facts[a] = b
        end
else
        if combo_info.empty?
                puts "Found no information for this host in Puppet, Cobbler, or Racktables...sure you got the name right?"
                exit
        end
        facts = combo_info
end

#Okay, we have a hash or all facts.
#Make second hash of specific facts


facts2 = Hash.new
if options[:all] == true
  facts2 = facts
else
values.each do |val|
  facts2[val] = facts[val]
end
end

is_hypervisor(facts,facts2,values)
is_virtual(facts2,values,puppet_url)
output(options,values,facts2)
