whatis
======

whatis is a simple wrapper around the PuppetDB v2 query API. Its purpose is to take a hostname/node name as an argument, and attempt to look it up on puppetdb and return some key info about it. 

whatis can take a short hostname, and try to look up its fqdn, or can take an fqdn. It can be cusomtized with multiple domains to try to complete with. It has a base list of facts to return, which acn be expanded, and can be expanded  dynamically (think, if fact_X == true, show fact_X, or fact_y, or both). 

whatis can also show ALL the facts for a system, and can output in json or yaml to be fed into other programs if desiered.


