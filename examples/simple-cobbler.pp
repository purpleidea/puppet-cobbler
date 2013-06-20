# this is your basic puppet-cobbler usage, you might need to tweak things a bit
# objects which aren't specified, but already exist in cobbler, will be purged!
class { '::cobbler':
	web => true,
	koan => true,
	debian => false,
	shorewall => true,
	httpport => 80,
	# NOTE: openssl passwd -1 -salt `pwgen 8 1` 'password'	# use your own!
	password => '$1$jietowon$c6BsPZKSFcFafdLZ.zMzB0'	# use your own!
	#puppetcapath => "...",
	puppetsign => true,
	puppetclean => true,
	puppetversion => '3',		# use puppet agent instead of puppetd
	authentication => 'testing',	# testing
	authorization => 'allowall',
}

cobbler::import { 'centos6.4-x86_64':
	mirror => 'http://<pick your own>/6.4/os/x86_64/',
	ksmeta => ['puppet_auto_setup=1'],	# add, but gets removed as dupe
	kopts => ['console=ttyS0,115200'],
	kopts_installer => ['console=ttyS0,115200'],
	breed => 'redhat',
	updates => false,	# we'll build it manually ourself
	profile => false,	# we'll build it manually ourself
	addrepo => true,	# this should build a repo of the same $name
	httpfakeimport => true,	# MAGIC! do a manual import using http!
}

# this gets built by import, but you could specify it manually yourself instead
#cobbler::distro { 'centos6.4-x86_64':
#	#kernel => '...',
#	#initrd => '...',
#	arch => 'x86_64',
#	#kopts_installer => ['console=ttyS0,115200'],
#	ksmeta => ['puppet_auto_setup=1'],
#	kopts => ['console=ttyS0,115200'],
#	#breed => 'redhat',
#}

# this can get built by import if you set profile => true. this is puppet magic
cobbler::profile { 'centos6.4-x86_64':	# main generic profile
	distro => 'centos6.4',
	arch => 'x86_64',
	repos => 'centos6.4-x86_64',	# TODO
	kickstart => 'ks',		# must match a cobbler::kickstart name!
	nssearch => 'example.com',
	#virtpath => "...",
}

# the included template needs improvement, but you can specify your own file...
cobbler::kickstart { 'ks':
	autopart => false,
	partboot => true,
	partswap => true,
	parthome => true,
	packages => [
		# make your own list, these are some useful things
		'screen',
		'vim-enhanced',
		'bash-completion',
		'git',
		'wget',
		'file',
		'man',
		'tree',
		'rsync',
		'nmap',
		'tcpdump',
		'htop',
		'lsof',
		'telnet',
		'mlocate',
		'openssh-clients',
		'bind-utils',
		'koan'
	],
	#postinstall => [...],
}

# build a system, remember systems which are not listed will get purged!
cobbler::system { 'test1':
	profile => 'centos6.4-x86_64',
	macaddress => '00:11:22:33:44:55',
	ipaddress => '203.0.113.42',
	netmask => '255.255.255.0',
	gateway => '203.0.113.253',
	dhcp => false,				# static ip
	virtpath => sprintf("%s/test1.raw", regsubst('/shared/vm/', '\/$', '')),
	virtram => '2048',
	virtcpus => '2',
	netboot => false,			# use koan
}

