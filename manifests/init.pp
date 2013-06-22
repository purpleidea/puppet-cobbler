# Cobbler templating module by James
# Copyright (C) 2012-2013+ James Shubin
# Written by James Shubin <james@shubin.ca>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# NOTE: ports used: tftp(udp:69), web(tcp:80), rsync(tcp:873), xmlrpc(tcp:25151)

# TODO: use fence tools; they are required to use the (optional) power management features. install cman or fence-agents to use them

# TODO: RUNONCE: cobbler check

# TODO: remove any unnecessary require => Package['cobbler'] if they are still litered around.

# TODO: cobbler hardlink (investigate this!)

# XXX: consider using the $watch, $manage and $*_excludes style architecture
# as used in my puppet-ipa, here. add true diff.py matching too.

class cobbler::vardir {	# module vardir snippet
	if "${::puppet_vardirtmp}" == '' {
		if "${::puppet_vardir}" == '' {
			# here, we require that the puppetlabs fact exist!
			fail('Fact: $puppet_vardir is missing!')
		}
		$tmp = sprintf("%s/tmp/", regsubst($::puppet_vardir, '\/$', ''))
		# base directory where puppet modules can work and namespace in
		file { "${tmp}":
			ensure => directory,	# make sure this is a directory
			recurse => false,	# don't recurse into directory
			purge => true,		# purge all unmanaged files
			force => true,		# also purge subdirs and links
			owner => root,
			group => nobody,
			mode => 600,
			backup => false,	# don't backup to filebucket
			#before => File["${module_vardir}"],	# redundant
			#require => Package['puppet'],	# no puppet module seen
		}
	} else {
		$tmp = sprintf("%s/", regsubst($::puppet_vardirtmp, '\/$', ''))
	}
	$module_vardir = sprintf("%s/cobbler/", regsubst($tmp, '\/$', ''))
	file { "${module_vardir}":		# /var/lib/puppet/tmp/cobbler/
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${tmp}"],	# File['/var/lib/puppet/tmp/']
	}
}

class cobbler (
	#
	#	general control settings
	#
	$web = true,
	$koan = true,			# TODO: is koan even needed on the server ?
	$rsync = false,			# use this server as an rsync mirror	# FIXME: should we add uid=nobody, etc, etc... to rsync.template ?
	$anamon = false,		# enable ANAconda MONitoring server
	$emailreport = true,		# email build reports
	$buildiso = false,		# TODO: change default to true once we have this tested and can confirm it works
	$debian = false,
	$shorewall = false,
	$zone = 'net',			# TODO: allow for a list of zones
	$allow = 'all',			# TODO: allow for a list of ip's per zone

	#
	#	settings
	#
	$server = '',			# if blank, settings will use the $fqdn
	$email = ['root@localhost'],	# email machine build reports to list
	# cobbler has various sample kickstart templates stored
	# in /var/lib/cobbler/kickstarts/. This controls
	# what install (root) password is set up for those
	# systems that reference this variable. The factory
	# default is 'cobbler' and cobbler check will warn if
	# this is not changed.
	# TODO: verify this openssl tool works properly; generate salt randomly
	# openssl passwd -1 -salt 'random-phrase-here' 'your-password-here'
	$password = '$1$mF86/UHC$WvcIcX2t6crBz2onWxyac.',	# default pass
	# FIXME: you currently need to modify the httpd listen setting manually
	$httpport = 80,			# port that apache is running on

	#
	#	virtualization defaults
	#
	$bridge = 'br0',		# default bridge for koan installs
	$virtautostart = false,		# autostart vm guests on host boot
	$virtram = 2048,		# default virt ram in MB
	$virtfilesize = 500,		# default virt file size in GB

	#
	#	other
	#
	$puppetcapath = '/usr/sbin/puppetca',	# ${vardir}/puppetca.sh
	$puppetsign = false,		# sign puppet certificates on install
	$puppetclean = false,		# clobber old puppet certs on reinstall
	$puppetserver = '',		# choose a --server arg for puppet runs
	$puppetversion = 3,		# use new style puppet agent in snippet
	$func = false,			# TODO: add func support at some point
	$scmtrack = false,		# false to disable
	$pxemenu = false,

	#
	#	authentication / authorization
	#
	$authentication = 'denyall',
	$authorization = 'allowall',

	#
	#	special
	#
	$offlineloaders = false,	# get loaders offline from puppet dir ?
	$packages_defaults = []		# list of essential packages to install

	# TODO?: change kernel_options to add console=ttyS0,38400 or 115200
	# TODO: configure ldap support in settings file
	# TODO: configure management system integration (like puppet)
	# TODO: dhcp integration
	# TODO: dns integration
	# TODO: add require_https options for cobbler-web ?
	# TODO: force https for cobbler-web (see rewrite rule @: https://fedorahosted.org/cobbler/wiki/CobblerWebInterface )
) {
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	$FW = '$FW'			# make using $FW in shorewall easier

	$rsync_ensure = $rsync ? {
		true => present,
		default => absent,
	}

	$rsync_enabled = $rsync ? {
		true => '1',
		default => '0',
	}

	$anamon_enabled = $anamon ? {
		true => '1',
		default => '0',
	}

	$emailreport_enabled = $emailreport ? {
		true => '1',
		default => '0',
	}

	$cobbler_server = $server ? {
		'' => "${fqdn}",		# if left blank, use this
		default => "${server}",
	}

	$virt_auto_boot = $virtautostart ? {
		true => '1',
		default => '0',
	}

	$sign_puppet_certs_automatically = $puppetsign ? {
		true => '1',
		default => '0',
	}

	$remove_old_puppet_certs_automatically = $puppetclean ? {
		true => '1',
		default => '0',
	}

	$scm_track_enable = $scmtrack ? {
		false => '0',
		default => '1',
	}

	$scm_track_mode = $scmtrack ? {
	# NOTE: add scm's to this list as they are supported
		'hg' => 'hg',
		'mercurial' => 'hg',
		default => 'git',
	}

	$scm = $scmtrack ? {
	# NOTE: add scm's to this list as they are supported
		'hg' => 'mercurial',
		'mercurial' => 'mercurial',
		'git' => 'git',		# NOTE: it's package git-core on fedora
		default => false,
	}

	$enable_menu = $pxemenu ? {
		true => '1',
		default => '0',
	}

	# TODO: add a facility to generate the /etc/cobbler/users.digest file
	$authn = $authentication ? {
		'denyall' => 'authn_denyall',		# no one (default)
		'configfile' => 'authn_configfile',	# use /etc/cobbler/users.digest (for basic setups)
		'passthru' => 'authn_passthru',		# ask Apache to handle it (used for kerberos)
		'ldap' => 'authn_ldap',			# authenticate against LDAP
		'spacewalk' => 'authn_spacewalk',	# ask Spacewalk/Satellite (experimental)
		'testing' => 'authn_testing',		# username/password is always testing/testing (debug)
		default => "${authentication}",
	}

	$authz = $authorization ? {
		'allowall' => 'authz_allowall',		# full access for all authenticated users (default)
		'ownership' => 'authz_ownership',	# use users.conf, but add object ownership semantics
		default => "${authorization}",
	}

	# FIXME: once i ran mkdir /tftpboot but i've also tried this symlink...
	file { '/tftpboot':	# this directory seems to be needed for cobbler
		ensure => '/var/lib/tftpboot/',	# ln -s /var/lib/tftpboot/ /tftpboot
		before => Package['cobbler'],
	}

	# cobbler package pulls in deps
	package { 'cobbler':
		ensure => present,
		before => [
			Service['cobblerd'],
			File["${vardir}/"],
		],
		notify => Exec['cobbler-get-loaders'],	# run once, at least
	}

	# provides the /usr/sbin/semanage executable
	package { 'policycoreutils-python':
		ensure => present,
	}

	# TODO: re-enable selinux at some point; currently cobbler behaves badly with it on
	class { '::selinux::config':
		selstate => 'permissive',
		seltype => 'targeted',
		before => Service['cobblerd'],
	}

	# one time command needed for cobbler setup
	exec { '/usr/sbin/semanage fcontext -a -t public_content_t "/var/lib/tftpboot/.*"':
		refreshonly => true,
		logoutput => on_failure,
		require => [Package['cobbler'], Package['policycoreutils-python']],
	}

	# one time command needed for cobbler setup
	exec { '/usr/sbin/semanage fcontext -a -t public_content_t "/var/www/cobbler/images/.*"':
		refreshonly => true,
		logoutput => on_failure,
		require => [Package['cobbler'], Package['policycoreutils-python']],
	}

	if $web {
		package { 'cobbler-web':
			ensure => present,
			before => Service['cobblerd'],
		}

		# one time command needed for cobbler-web setup
		exec { '/usr/sbin/semanage fcontext -a -t httpd_sys_content_rw_t "/var/lib/cobbler/webui_sessions/.*"':
			refreshonly => true,
			logoutput => on_failure,
			require => [Package['cobbler-web'], Package['policycoreutils-python']],
		}
	}

	if $koan {
		# NOTE: bug in current cobbler version, xmlrpc is only listening on 127.0.0.1, workaround: 'koan --port=80'
		package { 'koan':
			ensure => present,
			before => Service['cobblerd'],
		}
	}

	# TODO: test buildiso and ensure it works
	#if $buildiso {
		# NOTE: this seems to be needed for main cobbler so i moved it!
	package { 'syslinux':
		ensure => present,
		before => Service['cobblerd'],
	}
	#}

	if $debian {	# if false, then *don't* trigger package remove
		package { 'debmirror':
			ensure => present,
			before => Service['cobblerd'],
		}

	# TODO: comment 'dists' on /etc/debmirror.conf for proper debian support
	# TODO: comment 'arches' on /etc/debmirror.conf for proper debian support
	}

	if $scm {
		package { $scm:
			ensure => present,
			before => Service['cobblerd'],
		}
	}

	service { 'cobblerd':
		enable => true,			# start on boot
		ensure => running,		# ensure it stays running
		hasstatus => true,		# use status command to monitor
		hasrestart => true,		# use restart, not start; stop
		require => Package['cobbler'],
	}

	service { 'httpd':
		enable => true,			# start on boot
		ensure => running,		# ensure it stays running
		hasstatus => true,		# use status command to monitor
		hasrestart => true,		# use restart, not start; stop
		require => Package['cobbler'],
	}

	service { 'xinetd':			# used for rsync and tftp
		enable => true,
		ensure => running,
		hasstatus => true,
		hasrestart => true,
	}

	# setsebool -P httpd_can_network_connect=1
	selboolean { 'httpd_can_network_connect':
		persistent => true,
		value => on,
		require => Service['httpd'],
	}

	# NOTE: this file gets generated by new versions of cobbler (2.2+)
	# TODO: remove file from git if permanently unused...
	#file { '/etc/xinetd.d/tftp':	# requires UDP port 69
	#	source => 'puppet:///modules/cobbler/tftp',	# disable=no
	#	owner => root, group => root, mode => 644,	# u=rw,go=r
	#	backup => false,
	#	ensure => present,
	#	notify => Service['xinetd'],
	#}

	file { '/etc/xinetd.d/rsync':
		source => 'puppet:///modules/cobbler/rsync',	# disable=no
		owner => root, group => root, mode => 644,	# u=rw,go=r
		backup => false,
		ensure => $rsync_ensure,
		notify => Service['xinetd'],
	}

	# copy loaders from the puppet files cache. update this occasionally...
	if $offlineloaders {
		file { '/var/lib/cobbler/loaders/':
			ensure => directory,	# make sure this is a directory
			recurse => true,	# recursively manage directory
			purge => true,		# purge all unmanaged files
			force => true,		# also purge subdirs and links
			owner => root, group => root, mode => 644, backup => false,
			source => 'puppet:///modules/cobbler/loaders/',
			before => Service['cobblerd'],
			require => Package['cobbler'],
		}
	}

	# HACK: installs/updates all the loaders into /var/lib/cobbler/loaders/
	cron { 'cobbler-loaders':
		# TODO: we should probably add --force to update anything stale
		# from a possible initial cache sync if offlineloaders was used
		command => '/usr/bin/cobbler get-loaders',
		user => root,
		monthday => 1,			# run every month
		hour => 23,			# just before midnight
		ensure => $offlineloaders ? {
			true => absent,
			default => present,
		}
	}

	# FIXME: this should check to see if there are loaders and if it needs to be run...
	exec { '/usr/bin/cobbler get-loaders':
		refreshonly => true,
		logoutput => on_failure,
		require => Package['cobbler'],
		alias => 'cobbler-get-loaders',
	}

	# include this 'file' (directory) so that we can reference it below
	file { '/var/lib/cobbler/':
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => false,			# don't purge unmanaged files
		force => false,			# don't purge subdirs and links
		# omit user, group and mode so that this doesn't modify them
		notify => Exec['cobbler-sync'],
		require => Package['cobbler'],
	}

	# new version of this snippet until upstream. 100% backwards compatible
	file { '/var/lib/cobbler/snippets/puppet_register_if_enabled':
		source => 'puppet:///modules/cobbler/puppet_register_if_enabled.snippet',
		owner => root, group => root, mode => 644,	# u=rw,go=r
		backup => false,
		require => File['/var/lib/cobbler/'],
		ensure => present,
	}

	# run 'cobbler sync' after making any changes to the configuration
	# files to ensure those changes are applied to the environment.
	# Sync should be run whenever files in /var/lib/cobbler are manually
	# edited (which is not recommended except for the settings file) or
	# when making changes to kickstart files. In practice, this should not
	# happen often, though running sync too many times does not cause any
	# adverse effects. If using cobbler to manage a DHCP and/or DNS server
	# sync does need to be run after systems are added to regenerate and
	# reload the DHCP/DNS configurations.
	exec { '/usr/bin/cobbler sync':
		refreshonly => true,
		logoutput => on_failure,
		subscribe => File['/var/lib/cobbler/'],
		require => Package['cobbler'],
		alias => 'cobbler-sync',
	}

	file { '/etc/cobbler/settings':
		content => template('cobbler/settings.erb'),
		owner => root,
		group => root,
		mode => 664,		# ug=rw,o=	# TODO: need o=r for some reason. Figure out correct perms
		ensure => present,
		notify => Service['cobblerd'],
		require => Package['cobbler'],
	}

	file { '/etc/cobbler/modules.conf':
		content => template('cobbler/modules.conf.erb'),
		owner => root,
		group => root,
		mode => 644,		# u=rw,go=r
		ensure => present,
		notify => [Service['cobblerd'], Exec['cobbler-sync']],
		require => Package['cobbler'],
	}

	file { '/etc/cobbler/tftpd.template':
		content => template('cobbler/tftpd.template.erb'),
		owner => root,
		group => root,
		mode => 644,		# u=rw,go=r
		ensure => present,
		notify => [Service['cobblerd'], Exec['cobbler-sync']],
		require => Package['cobbler'],
	}

	# FIXME: consider allowing only certain ip's to the http server (and maybe xmlrpc?)
	# NOTE: don't serve tftp on the public net!
	if $shorewall {
		if $allow == 'all' {
			$net = "${zone}"
		} else {
			$net = is_array($allow) ? {
				true => sprintf("${zone}:%s", join($allow, ',')),
				default => "${zone}:${allow}",
			}
		}
		####################################################################
		#ACTION      SOURCE DEST                PROTO DEST  SOURCE  ORIGINAL
		#                                             PORT  PORT(S) DEST
		shorewall::rule { 'tftp': rule => "
		TFTP/ACCEPT  ${net}    $FW
		", comment => 'Allow TFTP for cobbler'}

		shorewall::rule { 'xmlrpc': rule => "
		ACCEPT       ${net}    $FW                tcp   25151
		", comment => 'Allow XMLRPC for cobbler'}

		# FIXME: change this to HTTPS
		shorewall::rule { 'http': rule => "
		#HTTPS/ACCEPT  ${net}    $FW	# FIXME: use this setting!
		#HTTP/ACCEPT  ${net}    $FW
		ACCEPT  ${net}    $FW    tcp    ${httpport}
		", comment => 'Allow web console for cobbler'}

		if $rsync {
			# rsync can be used as a mirror server
			shorewall::rule { 'rsync': rule => "
			Rsync/ACCEPT ${net}    $FW
			", comment => 'Allow Rsync for cobbler'}
		}
	}

	# All the object classes are included here, so that if the last define()
	# gets removed, then the class can still cause the object to be removed.
	include cobbler_import
	include cobbler_distro
	include cobbler_realrepo
	include cobbler_packages
	include cobbler_kickstart
	include cobbler_profile
	include cobbler_system
	include cobbler_system_netboot_collect
}

class cobbler_import {

	# directory of import tags which should exist (as managed by puppet)
	#file { "${vardir}/imports/":
	#	ensure => directory,		# make sure this is a directory
	#	recurse => true,		# recursively manage directory
	#	purge => true,			# purge all unmanaged files
	#	force => true,			# also purge subdirs and links
	#	owner => root, group => nobody, mode => 600, backup => false,
	#	notify => Exec['cobbler-clean-imports'],
	#	require => File["${vardir}/"],
	#}
}

define cobbler::import(
	$basepath = '',	# eg: rsync://mirror.csclub.uwaterloo.ca/centos/6.3/
	$mirror = '',	# alternative to $basepath which uses the value directly
	$kopts_installer = [],	# installer os kopts
	$kopts = [],		# installed os kopts
	$ksmeta = [],
	$breed = 'redhat',
	$updates = true,	# do we want to add the updates repository ?
	$profile = true,	# do we want to save the default profile ?
	$addrepo = undef,	# this adds the main repo so that it's all here
	$httpfakeimport = false	# attempt to fake an import, useful for http
) {
	include 'cobbler_import'

	# NOTE: this logic could be much more complex. this is perfect for now.
	# NOTE: if either distro or arch could contain a dash, we need a bugfix
	$split = split($name, '-')	# do some $name parsing
	$distro = $split[0]		# distro
	$arch = $split[1]		# arch

	if ! ( "${distro}-${arch}" == "${name}" ) {
		fail('The import $name must match a $distro-$arch pattern.')
	}

	if ( "${basepath}" == '' ) and ( "${mirror}" == '' ) {
		fail('You must specify either $basepath or $mirror.')
	}

	if ( "${basepath}" != '' ) and ( "${mirror}" != '' ) {
		fail('You must specify either $basepath or $mirror.')
	}

	# smart 'default' based on if httpfakeimport is true/false.
	$valid_addrepo = $addrepo ? {
		true => true,			# if set true, then it is true
		false => false,			# if false, then keep it false
		default => $httpfakeimport ? {	# if undefined then we choose:
			true => true,		# true if using httpfakeimport
			default => false,	# and false if not using this!
		}
	}

	# TODO: this path manipulation stuff should be different, depending on
	# the $breed variable. add more breeds and switch based on that var.
	if "${mirror}" != '' {
		$fixed_path = sprintf("%s/", regsubst($mirror, '\/$', ''))	# ensure trailing slash
		$os_path = "${fixed_path}"
		if $updates {
			# attempt to try and generate the updates path...
			# $mirror pattern: uri://<host>/p1/p2/pN/$distro-$arch/
			# builds: uri://<host>/p1/p2/pN/${distro}updates-$arch/
			$token_tail = inline_template("<%= File.split('${os_path}')[1] %>")
			$token_split = split($token_tail, '-')	# do some parsing
			$token_distro = $token_split[0]		# distro
			$token_arch = $token_split[1]		# arch
			if ! ( "${token_distro}-${token_arch}" == "${token_tail}" ) {
				$updates_path = ''	# disable
				warning('The $mirror tail must match a $distro-$arch pattern to generate updates repo.')
			} else {
				$token_head = inline_template("<%= File.split('${os_path}')[0] %>")
				$updates_path = "${token_head}/${token_distro}updates-${token_arch}/"
			}
		} else {
			$updates_path = ''	# disable
		}

	} # else...
	if "${basepath}" != '' {
		$fixed_path = sprintf("%s/", regsubst($basepath, '\/$', ''))	# ensure trailing slash
		$os_path = "${fixed_path}os/${arch}/"
		$updates_path = "${fixed_path}updates/${arch}/"
	}

	# NOTE: this is probably only useful when using $httpfakeimport...
	if $valid_addrepo {	# add the main repo as a bonus to complement our import
		cobbler::repo { "${distro}-${arch}":
			mirror => "${os_path}",
		}
	}

	# this attempts to get the images/pxeboot/{initrd.img,vmlinuz} files...
	if $httpfakeimport {
		$url = "${fixed_path}images/"
		$cut = inline_template("<%= URI('${url}').path.split('/').select { |x| x != '' }.count() %>")	# require 'uri'
		$dst = "/var/www/cobbler/ks_mirror/${distro}-${arch}/"	# import

		# TODO: add more advanced logic here based on $breed...
		$kernel = $breed ? {
			'redhat' => "${dst}images/pxeboot/vmlinuz",	# centos
			default => '',
		}
		$initrd = $breed ? {
			'redhat' => "${dst}images/pxeboot/initrd.img",	# centos
			default => '',
		}
		if "${kernel}" == '' {
			fail('Unable to autodetect $kernel path.')
		}
		if "${initrd}" == '' {
			fail('Unable to autodetect $initrd path.')
		}

		file { "${dst}":			# this is an mkdir $dst
			ensure => directory,		# make sure this is a directory
			recurse => false,
			purge => false,
			force => false,
			owner => root, group => root, mode => 644, backup => false,
			before => Exec["cobbler-import-${name}"],
			require => Package['cobbler'],
		}

		# NOTE: cheat and symlink in the import things into the repo...
		file { "/var/www/cobbler/repo_mirror/${distro}-${arch}/images/":
			ensure => "${dst}images/",
			require => File["${dst}"],
		}

		# TODO: if the wget gets interrupted and a file is partially
		# downloaded, it won't automatically re-download unti you rm
		# the partial file manually... in some magical future we md5
		exec { "/usr/bin/wget --quiet --recursive --execute robots=off --wait=1 --retry-connrefused --timestamping --no-parent --no-host-directories --cut-dirs=${cut} --reject 'html,*html*,robots.txt' --directory-prefix='${dst}images/' '${url}'":
			logoutput => on_failure,
			# do these two files exist on fs as gt-zero size ?
			unless => "/usr/bin/test -s '${kernel}' && /usr/bin/test -s '${initrd}'",
			#notify => Exec['cobbler-sync'],	# TODO: is this necessary ?
			alias => "cobbler-import-${name}",	# same as below
			timeout => 900,				# 10 min * 1.5
			# we require this repo, since it's the install url too!
			require => Cobbler::Repo["${distro}-${arch}"],
			#require => File["${dst}"],	# done with 'before'
			#require => Package['cobbler'],	# done by $dst above...
		}

	} else {
		# run an import...
		# NOTE: The last part after the '&&' is because the cobbler import command doesn't appropriately return true/false. This is a cobbler BUG.
		exec { "/usr/bin/cobbler import --name=${name} --path=${os_path} && /usr/bin/cobbler distro list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -":
			logoutput => on_failure,
			unless => "/usr/bin/cobbler distro list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if import has happened
			notify => Exec['cobbler-sync'],	# TODO: is this necessary ?
			require => Package['cobbler'],
			alias => "cobbler-import-${name}",
			timeout => 0,	# TODO: should we set a very long timeout instead?
			#require => Exec['cobbler-get-loaders'],	# FIXME: i think loaders are required for import (verify this!)
		}
		$kernel = ''	# disable, this is automatic
		$initrd = ''	# disable, this is automatic
	}

	# build a distro object (to match the distro that import already made!)
	cobbler::distro { "${name}":
		kernel => $kernel ? {
			'' => undef,	# leave out
			default => "${kernel}",
		},
		initrd => $initrd ? {
			'' => undef,	# leave out
			default => "${initrd}",
		},
		arch => "${arch}",
		kopts_installer => $kopts_installer,
		kopts => $kopts,
		ksmeta => $ksmeta,
		ksmeta_defaults => $httpfakeimport ? {
			# NOTE: instead of re-copying over a distro, just link!
			true => ["tree=http://@@server@@/cobbler/repo_mirror/${distro}-${arch}", 'puppet_auto_setup=1'],	# FIXME: can the $tree variable be moved to use https instead?
			default => undef,
		},
		breed => "${breed}",
		puppet_caller => 'cobbler::import',
		require => Exec["cobbler-import-${name}"],
	}

	# build the updates object (so your distro isn't out of date)
	if $updates and ( "${updates_path}" != '' ) {
		cobbler::repo { "${distro}updates-${arch}":
			mirror => "${updates_path}",
			require => Cobbler::Distro["${name}"],
		}
	}

	# NOTE: the 'cobbler import' will also generate a profile...
	# this part edits it so that it's sane.
	if $profile {
		cobbler::profile { "${name}":
			distro => "${distro}",
			arch => "${arch}",
			repos => ["${distro}updates-${arch}"],
			kopts => $kopts,
		}
	}
}

class cobbler_distro {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# directory of distro tags which should exist (as managed by puppet)
	file { "${vardir}/distros/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		notify => Exec['cobbler-clean-distros'],
		require => File["${vardir}/"],
	}

	# these are template variables for the clean.sh.erb script
	$id_dir = 'distros'
	$ls_cmd = '/usr/bin/cobbler distro list | /usr/bin/tr -d " "'	# show cobbler distros
	$rm_cmd = '/usr/bin/cobbler distro remove --name='		# delete cobbler distros
	$fs_chr = ' '
	$suffix = '.distro'
	$regexp = []
	$ignore = []

	# build the clean script
	file { "${vardir}/clean-distros.sh":
		content => template('cobbler/clean.sh.erb'),
		owner => root,
		group => nobody,
		mode => 700,			# u=rwx
		backup => false,		# don't backup to filebucket
		ensure => present,
		require => File["${vardir}/"],
	}

	# run the cleanup
	exec { "${vardir}/clean-distros.sh":
		logoutput => on_failure,
		refreshonly => true,
		require => File["${vardir}/clean-distros.sh"],
		alias => 'cobbler-clean-distros',
	}
}

define cobbler::distro(
	$kernel = '',		# path
	$initrd = '',		# path
	$arch = '',		# x86_64, i686, etc... blank for no change
	$kopts_installer = [],	# installer os kopts
	$kopts = [],		# installed os kopts
	$kopts_defaults = [],
	$ksmeta = [],
	$ksmeta_defaults = ["tree=http://@@server@@/cblr/links/${name}", 'puppet_auto_setup=1'],	# FIXME: can the $tree variable be moved to use https instead?
	$breed = 'redhat',	# TODO: implement
	$puppet_caller = ''	# internal private var, don't use
) {
	include 'cobbler_distro'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	$args_kernel = $kernel ? {
		'' => '',			# if left blank, don't modify
		default => "--kernel=${kernel}",
	}

	$args_initrd = $initrd ? {
		'' => '',			# if left blank, don't modify
		default => "--initrd=${initrd}",
	}

	if ($puppet_caller == '') {	# if cobbler::distro is called manually
		# ... then require these args. cobbler::import can auto assign!
		if ($args_kernel == '') or ($args_initrd == '') {
			fail('You must specify $kernel and $initrd for new distros.')
		}
	}

	$args_arch = $arch ? {
		'x86_64' => '--arch=x86_64',
		'x86' => '--arch=x86',
		'i686' => '--arch=x86',		# add i686 for sanity
		'ia64' => '--arch=ia64',	# use elilo
		'ppc' => '--arch=ppc',		# use yaboot
		'ppc64' => '--arch=ppc64',	# use yaboot
		's390x' => '--arch=s390x',	# no pxeboot, but koan works
		default => '',			# if left blank, don't modify
	}

	$args01 = "${args_kernel}"
	$args02 = "${args_initrd}"
	$args03 = "${args_arch}"
	# NOTE: there is an intentional renaming happening here so that var:
	# 'kopts' has the same meaning across cobbler+puppet. If the distro,
	# profile and system 'kopts' don't mean the same, then fix this bug!
	$args04 = sprintf("--kopts='%s'", inline_template('<%= kopts_installer.sort.join(" ") %>'))
	$args05 = sprintf("--kopts-post='%s'", inline_template('<%= (kopts+kopts_defaults).sort.join(" ") %>'))
	$args06 = sprintf("--ksmeta='%s'", inline_template('<%= (ksmeta+ksmeta_defaults).uniq.sort.join(" ") %>'))

	# put all the args in an array, remove the empty ones, and join with spaces (this removes '  ' double spaces uglyness)
	$arglist = ["${args01}", "${args02}", "${args03}", "${args04}", "${args05}", "${args06}"]
	$args = inline_template('<%= arglist.delete_if {|x| x.empty? }.join(" ") %>')

	$requires = File["${vardir}/distros/"]	# simple requires

	file { "${vardir}/distros/${name}.distro":
		content => "${name}\n${args}\n",
		owner => root,
		group => nobody,
		mode => 600,	# u=rw,go=
		notify => Exec["cobbler-distroedit-${name}"],
		require => $requires,
		ensure => present,
	}

	exec { "/usr/bin/cobbler distro add --name=${name} ${args}":
		logoutput => on_failure,
		unless => "/usr/bin/cobbler distro list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if distro exists
		require => [
			File["${vardir}/distros/${name}.distro"],
			Package['cobbler'],
		],
		alias => "cobbler-distroadd-${name}",
	}

	exec { "/usr/bin/cobbler distro edit --name=${name} ${args}":
		refreshonly => true,
		logoutput => on_failure,
		require => [
			File["${vardir}/distros/${name}.distro"],
			Exec["cobbler-distroadd-${name}"],	# require a distro add, in case distro wasn't made yet
			Package['cobbler'],
		],
		alias => "cobbler-distroedit-${name}",
	}
}

class cobbler_realrepo {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# TODO: this reposync probably can be removed since cobbler::repo uses --only
	exec { '/usr/bin/cobbler reposync':
		refreshonly => true,
		logoutput => on_failure,
		require => Package['cobbler'],
		alias => 'cobbler-reposync',
		timeout => 0,		# TODO: pick a reasonable timeout
	}

	# keep the repositories up to date. cron frequency was arbitrary.
	cron { 'cobbler-reposync':
		command => '(/usr/bin/cobbler reposync --tries=3 --no-fail) > /dev/null 2>&1',	# TODO: make more noisy ?
		user => root,
		weekday => 'Thursday',		# run once a week
		hour => '23',			# in the evenings
		ensure => present,
	}

	# directory of repo tags which should exist (as managed by puppet)
	file { "${vardir}/repos/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		notify => Exec['cobbler-clean-repos'],
		require => File["${vardir}/"],
	}

	# these are template variables for the clean.sh.erb script
	$id_dir = 'repos'
	$ls_cmd = '/usr/bin/cobbler repo list | /usr/bin/tr -d " "'	# show cobbler repos
	$rm_cmd = '/usr/bin/cobbler repo remove --name='		# delete cobbler repo
	$fs_chr = ' '
	$suffix = '.repo'
	$regexp = []
	$ignore = []

	# build the clean script
	file { "${vardir}/clean-repos.sh":
		content => template('cobbler/clean.sh.erb'),
		owner => root,
		group => nobody,
		mode => 700,			# u=rwx
		backup => false,		# don't backup to filebucket
		ensure => present,
		require => File["${vardir}/"],
	}

	# run the cleanup
	exec { "${vardir}/clean-repos.sh":
		logoutput => on_failure,
		refreshonly => true,
		require => File["${vardir}/clean-repos.sh"],
		alias => 'cobbler-clean-repos',
	}

	# purge unmanaged repo data
	if versioncmp($puppetversion, '2.6.6') {	# selinux_ignore_defaults in 2.6.7
		file { '/var/www/cobbler/repo_mirror/':
			ensure => directory,		# make sure this is a directory
			recurse => true,		# recursively manage directory
			purge => true,			# purge all unmanaged files
			force => true,			# also purge subdirs and links
			backup => false,		# don't backup to filebucket
			# this option removes the slowness of puppet trying to lookup
			# selinux attributes for all of the files stored in the repo.
			selinux_ignore_defaults => true,
			notify => Service['cobblerd'],	# restart to notice db changes
			require => Package['cobbler'],
		}
	} else {
		file { '/var/www/cobbler/repo_mirror/':
			ensure => directory,		# make sure this is a directory
			recurse => true,		# recursively manage directory
			purge => true,			# purge all unmanaged files
			force => true,			# also purge subdirs and links
			backup => false,		# don't backup to filebucket
			notify => Service['cobblerd'],	# restart to notice db changes
			require => Package['cobbler'],
		}
	}
}

# this is the "real" repo object that gets used
define cobbler::realrepo(
	$mirror,
	$keepupdated = true,
	$subscribe = undef	# NOTE: this magic lets ::packages pass a variable to reposync to tell it what to subscribe to
) {
	include 'cobbler_realrepo'		# include to do some actions only once
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	$bool_keepupdated = $keepupdated ? {
		false => '0',
		default => '1',
	}

	$args = "--mirror=${mirror} --keep-updated=${bool_keepupdated}"

	file { "${vardir}/repos/${name}.repo":
		content => "${name}\n${args}\n",
		owner => root,
		group => nobody,
		mode => 600,	# u=rw,go=
		notify => Exec["cobbler-repoedit-${name}"],
		require => File["${vardir}/repos/"],
		ensure => present,
	}

	exec { "/usr/bin/cobbler repo add --name=${name} ${args}":
		logoutput => on_failure,
		unless => "/usr/bin/cobbler repo list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if repo exists
		before => File["/var/www/cobbler/repo_mirror/${name}"],
		notify => Exec["cobbler-reposync-${name}"],
		require => [
			File["${vardir}/repos/${name}.repo"],
			Package['cobbler'],
		],
		alias => "cobbler-repoadd-${name}",
	}

	exec { "/usr/bin/cobbler repo edit --name=${name} ${args}":
		refreshonly => true,
		logoutput => on_failure,
		before => File["/var/www/cobbler/repo_mirror/${name}"],
		notify => Exec["cobbler-reposync-${name}"],
		require => [
			File["${vardir}/repos/${name}.repo"],
			Exec["cobbler-repoadd-${name}"],	# require a repo add, in case repo wasn't made yet
			Package['cobbler'],
		],
		alias => "cobbler-repoedit-${name}",
	}

	# tag this directory as managed, so that it is not removed by the purge
	if versioncmp($puppetversion, '2.6.6') {	# selinux_ignore_defaults in 2.6.7
		file { "/var/www/cobbler/repo_mirror/${name}":
			ensure => directory,
			backup => false,		# don't backup to filebucket
			# this option removes the slowness of puppet trying to lookup
			# selinux attributes for all of the files stored in the repo.
			selinux_ignore_defaults => true,
		}
	} else {
		file { "/var/www/cobbler/repo_mirror/${name}":
			ensure => directory,
			backup => false,		# don't backup to filebucket
		}
	}

	exec { "/usr/bin/cobbler reposync --only='${name}'":
		refreshonly => true,
		logoutput => on_failure,
		subscribe => $subscribe,	# receive events from cobbler::packages
		require => [
			Exec["cobbler-repoadd-${name}"],
			Package['cobbler'],
		],
		alias => "cobbler-reposync-${name}",
		timeout => 0,		# TODO: pick a reasonable timeout
	}
}

#
#	manage your own rpm repository without something heavy like pulpproject
#
class cobbler_packages {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	file { "${vardir}/packages/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${vardir}/"],
	}

	file { "${vardir}/empty/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		require => File["${vardir}/"],
	}

	# TODO: search for cachedir below. This is here for a future TODO
	#file { "${vardir}/packages_cache/":
	#	ensure => directory,		# make sure this is a directory
	#	recurse => true,		# recursively manage directory
	#	purge => true,			# purge all unmanaged files
	#	force => true,			# also purge subdirs and links
	#	owner => root, group => nobody, mode => 600, backup => false,
	#	require => File["${vardir}/"],
	#}
}

# TODO: check out the puppet yum repo: http://docs.puppetlabs.com/references/stable/type.html#yumrepo (maybe it will be useful?)
define cobbler::packages(
	$source,
	#$deltas = false,		# add the --deltas (drpm) flag to createrepo	# TODO?
	$autorepo = false
) {
	include 'cobbler_packages'	# include to do some actions only once
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# put the rpm's here
	file { "${vardir}/packages/${name}/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		#source => "${source}",		# puppet:///files/cobbler/...
		# have an empty source as a backup if $source is missing
		source => [
			"${source}",		# puppet:///files/cobbler/...
			"${vardir}/empty/",
		],
		#notify => Exec["cobbler-createrepo-${name}"],	# NOTE: commented out because it seems repodata gets done automatically by cobbler
		#before => Exec["cobbler-createrepo-${name}"],	# NOTE: commented out because it seems repodata gets done automatically by cobbler
		require => File["${vardir}/packages/"],
	}

	# NOTE: commented out because it seems repodata gets done automatically by cobbler
	## tag a repo dir so puppet doesn't erase it
	#file { "${vardir}/packages/${name}/repodata/":
	#	ensure => directory,		# make sure this is a directory
	#	recurse => false,		# recursively manage directory
	#	purge => false,			# purge all unmanaged files
	#	force => false,			# also purge subdirs and links
	#	#owner => root, group => nobody, mode => 600,	# TODO ???
	#	backup => false,
	#	notify => Exec["cobbler-createrepo-${name}"],
	#	require => File["${vardir}/packages/${name}/"],
	#}

	# TODO: someone could add cachedir support if they wanted it badly
	# eg: --cachedir ${vardir}/packages_cache/${name}/
	# NOTE: it would make sense to have a tidy{} happen on this directory
	# so that it wouldn't ever skyrocket in size with cruft. (if packages are removed)
	#file { "${vardir}/packages_cache/${name}/":
	#	ensure => directory,		# make sure this is a directory
	#	recurse => false,		# recursively manage directory
	#	purge => false,			# purge all unmanaged files
	#	force => false,			# also purge subdirs and links
	#	owner => root, group => nobody, mode => 600, backup => false,
	#	require => File["${vardir}/packages/"],
	#}

	# NOTE: commented out because it seems repodata gets done automatically by cobbler
	## run the createrepo command
	#exec { "/usr/bin/createrepo --update --checkts ${vardir}/packages/${name}/":
	#	refreshonly => true,
	#	logoutput => on_failure,
	#	#notify => Cobbler::Repo["${name}"],	# TODO: make this work in case it doesn't. The goal is have cobbler::repo notice the change
	#	#notify => EXEC: cobbler reposync --only='${name}'	# TODO
	#	require => File["${vardir}/packages/${name}/"],
	#	alias => "cobbler-createrepo-${name}",
	#}

	# automatically add the cobbler::repo
	if $autorepo {
		cobbler::realrepo { "${name}":
			mirror => "${vardir}/packages/${name}/",
			# keepupdated is disabled because changes in rpms from
			# puppet trigger their own reposync's to run anyways
			keepupdated => false,
			subscribe => File["${vardir}/packages/${name}/"],	# tell realrepo to listen to this folder (magic!)
			require => File["${vardir}/packages/${name}/"],
			#require => Exec["cobbler-createrepo-${name}"],	# NOTE: commented out because it seems repodata gets done automatically by cobbler
		}
	}
}

define cobbler::repo(
	$mirror,
	$keepupdated = true,
	$comment = ''	# TODO
) {
	# this check is important for catching poorly transformed repo hashes
	if "${mirror}" == '' {
		fail("Cobbler::Repo[${name}] is using an empty mirror value.")
	}

	# if this starts with 'puppet:///' create a cobbler::packages object, and then this repo
	# aka: if $mirror.startswith('puppet:///')
	if $mirror =~ /^puppet:\/\/\// {
		cobbler::packages { $name:
			source => "${mirror}",
			autorepo => true,
		}
	} else {
		# pass through to "real" repo object
		cobbler::realrepo { $name:
			mirror => $mirror,
			keepupdated => $keepupdated,
		}
	}
}

# TODO:
#class cobbler_snippet {
#
#}
#define cobbler::snippet {
#
#}

class cobbler_kickstart {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	$base = '/var/lib/cobbler/kickstarts/'
	$samples = [
		"${base}/default.ks",
		"${base}/legacy.ks",
		"${base}/pxerescue.ks",
		"${base}/sample_end.ks",
		"${base}/sample.ks",
		"${base}/sample.seed",
		"${base}/autoyast_sample.xml",
		"${base}/esxi4-ks.cfg",
		"${base}/esxi5-ks.cfg",
		"${base}/esxi_sample.ks",
	]
	# tag these files as managed, so they are not removed by the purge
	file { $samples:
		ensure => file,
	}

	# purge unmanaged kickstarts
	file { "${base}":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		notify => [Exec['cobbler-sync'], Service['cobblerd']],
		require => Package['cobbler'],
	}

	package { 'pykickstart':
		ensure => present,
	}

	# if this tag file is present, it means kickstarts haven't validated yet
	$tag = "${vardir}/validateks/kickstarts_are_unvalidated"

	# put tag tag file into a dir that does not purge
	file { "${vardir}/validateks/":
		ensure => directory,		# make sure this is a directory
		recurse => false,
		purge => false,			# don't purge the untagged tag!
		force => true,
		owner => root, group => nobody, mode => 600, backup => false,
		before => Exec['cobbler-validateks'],
		require => File["${vardir}/"],
	}

	# notify this exec to trigger kickstart validation
	exec { "/bin/date > '${tag}'":
		logoutput => on_failure,
		refreshonly => true,
		before => Exec['cobbler-validateks-exec'],
		notify => Exec['cobbler-validateks-exec'],	# optional
		require => Package['cobbler'],
		alias => 'cobbler-validateks',
	}


	# NOTE: ksvalidate returns a bad exit status, eg:
	# *** all kickstarts seem to be ok ***
	# !!! TASK FAILED !!!
	# this bug is fixed in git as: a4257b1ceaf627f6906efc7a16db7f418079a727
	# this command usually tells you if your rendered kickstarts are valid
	# once the Exec[cobbler-validateks] runs, this will exec until success!
	exec { "/usr/bin/cobbler validateks && /bin/rm -f '${tag}'":
		#refreshonly => true,
		logoutput => on_failure,
		# if tag exists, it means we need to do validation...
		onlyif => "/usr/bin/test -e '${tag}'",
		require => Package['pykickstart'],
		alias => 'cobbler-validateks-exec',
	}
}

# NOTE: this cobbler::kickstart is similar to virt::kickstart, so merge the two
# if possible or at least share code between them where it's possible to do so.
define cobbler::kickstart(
	# TODO: add more parameters here
	$source = false,	# source from a puppet:///files/cobbler/ks/ path instead
	$timezone = 'America/Montreal',
	#
	#	partitioning: if autopart is false, then the part_* are used
	#
	$efi = false,		# enable for a/an uefi/efi bios	# TODO: if efi is true, should we automatically enable gpt ?
	$gpt = false,		# enable gpt	# TODO: implement
	$autopart = true,	# by default we use autopart
	$osdrives = [],		# 'sda','sdb'
	$partboot = true,	# include a: part /boot --fstype=ext4
	$partswap = true,	# include a: part swap --recommended
	$parthome = true,	# include a: logvol /home --vgname=vg_00 --name=lv_home --fstype=ext4
	$partbootsize = 1024,	# size in mb	# TODO: default size ?
	$partrootsize = true,	# see below for valid values
	$parthomesize = 512,	# size in mb
	$partvar = false,	# include a: logvol /var --vgname=vg_00 --name=lv_var --fstype=ext4
	$partvarsize = true,	# see below for valid values
	$packages = [],		# a list of packages to install on kickstart
	$packages_defaults = '',# FIXME: undef would be ideal, but type(undef) returns string!
	$preinstall = [],	# a list of pre install commands to run
	$postinstall = [],	# a list of post install commands to run
	$comment = ''		# add a comment at the top of the ks file
) {
	# finds the file name in a complete path; eg: /tmp/dir/file => file
	$filename = regsubst($name, '(\/[\w.]+)*(\/)([\w.]+)', '\3')
	if "${name}" == "${filename}" {	# internal use ? (no path, if equal...)
		include 'cobbler_kickstart'
		$internal = true
		# NOTE: this commented code should do the same thing (original)
		#$basepath = '/var/lib/cobbler/kickstarts/'
		#$valid_basepath = regsubst($basepath, '\/$', '')	# remove trailing slash
		#$fullpath = "${valid_basepath}/${filename}.ks"	# has .ks ext.
		$fullpath = "/var/lib/cobbler/kickstarts/${name}.ks"	# new
	} else {
		$internal = false
		# NOTE: this commented code should do the same thing (original)
		# finds the basepath in a complete path; eg: /tmp/dir/file => /tmp/dir/
		#$basepath = regsubst($name, '((\/[\w.-]+)*)(\/)([\w.-]+)', '\1')
		#$valid_basepath = regsubst($basepath, '\/$', '')	# remove trailing slash
		#$fullpath = "${valid_basepath}/${filename}"	# to .ks ext.
		$fullpath = "${name}"					# new
	}

	if ($partrootsize == true) {
		# useful when we don't have a /var partition
		$partroot_spec = '--grow --size=1'	# grow to maximum size
	} elsif ($partrootsize == false) {
		# useful when we want this fixed, and we want /var to grow
		$partroot_spec = '--size=51200 --maxsize=51200'	# TODO: default size ?
	} elsif ($partrootsize > 0 and $partrootsize <= 100) {
		# since we don't care about < 100mb partitions, use a percent!
		$partroot_spec = "--percent=${partrootsize}"
	} elsif ($partrootsize > 100) {
		# specify an exact size
		$partroot_spec = "--size=${partrootsize} --maxsize=${partrootsize}"
	} else {
		fail('You must specify a valid root partition size.')
	}

	if ($partvarsize == true) {
		# useful when we don't have a /var partition
		$partvar_spec = '--grow --size=1'	# grow to maximum size
	} elsif ($partvarsize == false) {
		# useful when we want this fixed, and we want / (root) to grow
		$partvar_spec = '--size=1048576 --maxsize=1048576'	# TODO: default size ?
	} elsif ($partvarsize > 0 and $partvarsize <= 100) {
		# since we don't care about < 100mb partitions, use a percent!
		$partvar_spec = "--percent=${partvarsize}"
	} elsif ($partvarsize > 100) {
		# specify an exact size
		$partvar_spec = "--size=${partvarsize} --maxsize=${partvarsize}"
	} else {
		fail('You must specify a valid /var partition size.')
	}

	# smart 'default' based on if $packages_defaults is modified or not
	$valid_packages_defaults = type($packages_defaults) ? {
		'undef' => $cobbler::packages_defaults,
		default => $packages_defaults,
	}

	# build normally from puppet template
	file { "${fullpath}":
		content => $source ? {
			false => template('cobbler/kickstart.ks.erb'),
			default => undef,
		},
		source => $source ? {
			false => undef,
			default => "${source}",
		},
		owner => root,
		group => root,
		mode => 644,		# u=rw,go=r
		ensure => present,
		notify => $internal ? {
			false => undef,
			default => [Exec['cobbler-validateks'], Exec['cobbler-sync']],
		},
		require => $internal ? {
			false => undef,
			default => Package['cobbler'],
		},
	}
}

class cobbler_profile {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# directory of profile tags which should exist (as managed by puppet)
	file { "${vardir}/profiles/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		notify => Exec['cobbler-clean-profiles'],
		require => File["${vardir}/"],
	}

	# these are template variables for the clean.sh.erb script
	$id_dir = 'profiles'
	$ls_cmd = '/usr/bin/cobbler profile list | /usr/bin/tr -d " "'	# show cobbler profiles
	$rm_cmd = '/usr/bin/cobbler profile remove --name='		# delete cobbler profile
	$fs_chr = ' '
	$suffix = '.profile'
	$regexp = []
	$ignore = []

	# build the clean script
	file { "${vardir}/clean-profiles.sh":
		content => template('cobbler/clean.sh.erb'),
		owner => root,
		group => nobody,
		mode => 700,			# u=rwx
		backup => false,		# don't backup to filebucket
		ensure => present,
		require => File["${vardir}/"],
	}

	# run the cleanup
	exec { "${vardir}/clean-profiles.sh":
		logoutput => on_failure,
		refreshonly => true,
		require => File["${vardir}/clean-profiles.sh"],
		alias => 'cobbler-clean-profiles',
	}
}

define cobbler::profile(
	$parent = '',			# you must select either parent, or
	$distro = '',			# distro and arch.
	$arch = 'x86_64',
	$repos = [],
	$kickstart = '',		# if '' use 'default', unless $parent exists
	$nameservers = [],		# name servers
	$nssearch = false,		# name server search
	$virtpath = false,		# default is: /var/lib/libvirt/images/
	# TODO:
	# --virt-file-size=gigabytes
	# --virt-ram=megabytes
	# --virt-type=string
	# --virt-cpus=integer
	# --virt-path=string
	# --virt-bridge=string
	$kopts = [],
	$ksmeta = [],
	$pxemenu = '',			# enable pxe menu ? true or false
	$serveroverride = ''		# specify a different cobbler server ip
) {
	include 'cobbler_profile'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# check ip and strip off cidr (if present) allowing hostnames to fly...
	$valid_serveroverride = stripcidr($serveroverride)

	if ($parent == '') and ($distro == '') {
		fail('You must choose either distro or parent.')
	}

	if ($parent == '') {
		$distro_arch = "${distro}-${arch}"
		$args01 = "--distro=${distro_arch}"
	} else {
		$args01 = "--parent=${parent}"
	}

	# if we are using the $parent argument, then we want to inherit the ks if it is blank ('')
	#if ($parent == '') {
	#	$args02 = $kickstart ? {
	#		'' => '--kickstart=/var/lib/cobbler/kickstarts/default.ks',	# if empty, then use the default (when no parent exists)
	#		default => "--kickstart=/var/lib/cobbler/kickstarts/${kickstart}.ks",	# if something, then use it
	#	}
	#} else {
	#	$args02 = $kickstart ? {
	#		'' => '',	# if empty, leave it empty
	#		default => "--kickstart=/var/lib/cobbler/kickstarts/${kickstart}.ks",	# if something, then use it
	#	}
	#}
	$args02 = $kickstart ? {	# no duplication, but a bit less clear
		'' => $parent ? {
			'' => '--kickstart=/var/lib/cobbler/kickstarts/default.ks',	# if empty, then use the default (when no parent exists)
			default => '',	# if empty, leave it empty (parent exists)
		},
		default => "--kickstart=/var/lib/cobbler/kickstarts/${kickstart}.ks",	# if something, then use it
	}

	$args03 = "${nameservers}" ? {	# if $nameservers == [], then $args3 = ''
		'' => '',
		default => sprintf("--name-servers='%s'", inline_template('<%= nameservers.sort.join(" ") %>')),
	}

	$args04 = $nssearch ? {
		false => '',
		default => "--name-servers-search='${nssearch}'",
	}
	$args05 = $virtpath ? {
		false => '',
		default => "--virt-path=${virtpath}",
	}

	$args06 = sprintf("--repos='%s'", inline_template('<%= repos.sort.join(" ") %>'))
	$args07 = sprintf("--kopts='%s'", inline_template('<%= kopts.sort.join(" ") %>'))
	$args08 = sprintf("--ksmeta='%s'", inline_template('<%= ksmeta.uniq.sort.join(" ") %>'))

	$args09 = $valid_serveroverride ? {
		'' => '',
		# BUG: --server-override is supposed to work, but it seems it's actually '--server'
		#default => "--server-override=${valid_serveroverride}",
		default => "--server=${valid_serveroverride}",
	}

	$args10 = $pxemenu ? {
		true => '--enable-menu=1',
		false => '--enable-menu=0',
		default => '',	# undef scenario; leave global default untouched
	}

	# put all the args in an array, remove the empty ones, and join with spaces (this removes '  ' double spaces uglyness)
	$arglist = ["${args01}", "${args02}", "${args03}", "${args04}", "${args05}", "${args06}", "${args07}", "${args08}", "${args09}", "${args10}"]
	$args = inline_template('<%= arglist.delete_if {|x| x.empty? }.join(" ") %>')
	# TODO: replace all these delete_if templates with: $args = join(delete($arglist, ''), ' ')

	# requires dependency tree:
	if $repos == [] {
	# branch: no repos
		$requires = $kickstart ? {
			'' => $parent ? {
				'' => Cobbler::Distro["${distro}-${arch}"],
				default => Cobbler::Profile[$parent],
			},
			default => $parent ? {
				'' => [Cobbler::Distro["${distro}-${arch}"], Cobbler::Kickstart[$kickstart]],
				default => [Cobbler::Kickstart[$kickstart], Cobbler::Profile[$parent]],
			},
		}

	} else {
	# branch: yes repos
		$requires = $kickstart ? {
			'' => $parent ? {
				'' => [Cobbler::Distro["${distro}-${arch}"], Cobbler::Repo[$repos]],
				default => [Cobbler::Repo[$repos], Cobbler::Profile[$parent]],
			},

			default => $parent ? {
				'' => [Cobbler::Distro["${distro}-${arch}"], Cobbler::Repo[$repos], Cobbler::Kickstart[$kickstart]],
				default => [Cobbler::Repo[$repos], Cobbler::Kickstart[$kickstart], Cobbler::Profile[$parent]],
			},
		}
	}

	# alternatively:
	# thanks to marut in #puppet for the hint about coercing the [] to ''
	#$requires = $kickstart ? {
	#	# no ks branch:
	#	'' => "${repos}" ? {
	#		'' => undef,				# no ks, no repos
	#		default => Cobbler::Repo[$repos],	# no ks, yes repos
	#	},
	#
	#	# yes ks branch:
	#	default => "${repos}" ? {
	#		'' => Cobbler::Kickstart[$kickstart],	# yes ks, no repos
	#		default => [Cobbler::Kickstart[$kickstart], Cobbler::Repo[$repos]],	# yes ks, yes repos
	#	},
	#}

	file { "${vardir}/profiles/${name}.profile":
		content => "${name}\n${args}\n",
		owner => root,
		group => nobody,
		mode => 600,	# u=rw,go=
		notify => Exec["cobbler-profileedit-${name}"],
		# FIXME: add in require => File["${vardir}/profiles/"]
		require => $requires,
		ensure => present,
	}

	exec { "/usr/bin/cobbler profile add --name=${name} ${args}":
		logoutput => on_failure,
		unless => "/usr/bin/cobbler profile list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if profile exists
		#notify => Exec['cobbler-sync'],	# not needed
		require => [
			File["${vardir}/profiles/${name}.profile"],
			Package['cobbler'],
		],
		alias => "cobbler-profileadd-${name}",
	}

	exec { "/usr/bin/cobbler profile edit --name=${name} ${args}":
		refreshonly => true,
		logoutput => on_failure,
		#notify => Exec['cobbler-sync'],	# not needed
		require => [
			File["${vardir}/profiles/${name}.profile"],
			Exec["cobbler-profileadd-${name}"],	# require a profile add, in case profile wasn't made yet
			Package['cobbler'],
		],
		alias => "cobbler-profileedit-${name}",
	}
}

class cobbler_system {
	include 'cobbler'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# directory of system tags which should exist (as managed by puppet)
	file { "${vardir}/systems/":
		ensure => directory,		# make sure this is a directory
		recurse => true,		# recursively manage directory
		purge => true,			# purge all unmanaged files
		force => true,			# also purge subdirs and links
		owner => root, group => nobody, mode => 600, backup => false,
		notify => Exec['cobbler-clean-systems'],
		require => File["${vardir}/"],
	}

	# these are template variables for the clean.sh.erb script
	$id_dir = 'systems'
	$ls_cmd = '/usr/bin/cobbler system list | /usr/bin/tr -d " "'	# show cobbler systems
	$rm_cmd = '/usr/bin/cobbler system remove --name='		# delete cobbler system
	$fs_chr = ' '
	$suffix = '.system'
	$regexp = []
	$ignore = []

	# build the clean script
	file { "${vardir}/clean-systems.sh":
		content => template('cobbler/clean.sh.erb'),
		owner => root,
		group => nobody,
		mode => 700,			# u=rwx
		backup => false,		# don't backup to filebucket
		ensure => present,
		require => File["${vardir}/"],
	}

	# run the cleanup
	exec { "${vardir}/clean-systems.sh":
		logoutput => on_failure,
		refreshonly => true,
		require => File["${vardir}/clean-systems.sh"],
		alias => 'cobbler-clean-systems',
	}
}

# FIXME: a system with the name 'default' has special properties...
define cobbler::system(
	$profile,
	$macaddress,			# mac address
	$dhcp = false,			# dhcp vs. static	# TODO: default to true ?
	$ipaddress = '',		# optional ip address
	$netmask = '',
	$gateway = '',
	$virtcpus = false,		# integer value (dimensionless)
	$virtram = false,		# integer value in megabytes
	$virtpath = false,		# this can be a complete path to an img
	$virtfilesize = false,		# integer value in gigabytes
	$kopts = [],
	$ksmeta = [],
	#$extras = [],
	$netboot = false,		# allow install from pxe boot ?
	$serveroverride = ''		# specify a different cobbler server ip
) {
	include 'cobbler_system'
	include cobbler::vardir
	#$vardir = $::cobbler::vardir::module_vardir	# with trailing slash
	$vardir = regsubst($::cobbler::vardir::module_vardir, '\/$', '')

	# FIXME: figure out if i can add netmask ('subnet') and gateway into a
	# parent profile. if not, then they'll unfortunately have to get added here

	# TODO: add ipv6 support
	case $ipaddress {
		/^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/(3[0-2]|[12]?[0-9])$/: {
			# with cidr
			if $dhcp == true {
				$valid_ipaddress = ''
				$valid_netmask = ''
			} else {
				$valid_ipaddress = "${1}.${2}.${3}.${4}"
				$cidr = "${5}"
				if ( $netmask != '' ) {
					fail('Netmask must be blank when IP address contains CIDR.')
				}
				$valid_netmask = inline_template("<%= IPAddr.new('255.255.255.255').mask(${cidr}).to_s %>")	# cidr -> netmask
			}
		}
		/^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/: {
			# no cidr
			if $dhcp == true {
				$valid_ipaddress = ''
				$valid_netmask = ''
			} else {
				#$valid_ipaddress = $ipaddress	# same as below
				$valid_ipaddress = "${1}.${2}.${3}.${4}"
				if $netmask =~ /^(((128|192|224|240|248|252|254)\.0\.0\.0)|(255\.(0|128|192|224|240|248|252|254)\.0\.0)|(255\.255\.(0|128|192|224|240|248|252|254)\.0)|(255\.255\.255\.(0|128|192|224|240|248|252|254)))$/ {
					$valid_netmask = $netmask
				} else {
					fail('A valid netmask is required.')
				}
				$cidr = inline_template("<%= IPAddr.new('${valid_netmask}').to_i.to_s(2).count('1') %>")
			}
		}
		/^$/: {
			# empty string, pass through
			$valid_ipaddress = ''
			$valid_netmask = ''
			if ( $netmask != '' ) {
				fail('If IP address is empty, netmask must be too!')
			}
		}
		default: {
			if $dhcp == true {
				$valid_ipaddress = ''
				$valid_netmask = ''
			} else {
				fail('If specifying an IP address, it must be syntactically correct.')
			}
		}
	}

	# check ip and strip off cidr (if present)
	case $gateway {	# TODO: add IPv6 support
		/^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/(3[0-2]|[12]?[0-9])$/: {
			# with cidr
			$valid_gateway = "${1}.${2}.${3}.${4}"
		}
		/^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/: {
			# no cidr
			$valid_gateway = $gateway
		}
		/^$/: {
			# empty string, pass through
			$valid_gateway = ''
		}
		default: {
			fail('$gateway must be either a valid IP address or empty.')
		}
	}

	# check ip and strip off cidr (if present) allowing hostnames to fly...
	$valid_serveroverride = stripcidr($serveroverride)

	# FIXME: perhaps I should obtain all this information from dhcp instead
	# NOTE: i am purposefully setting the hostname equal to the puppet name
	$args01 = "--profile=${profile} --hostname=${name} --mac=${macaddress}"

	# NOTE: the --netboot-enabled parameter should not go in the main args
	# because when the machine has booted, it can sometimes turn this off.
	# this is useful to prevent repeated: netboot, install, reboot cycles.
	$bool_netboot = $netboot ? {
		true => 'true',
		default => 'false',
	}
	# NOTE: I would have thought that allowing an empty ksmeta array would
	# erase the parent value of ksmeta, but apparently this does not occur
	# and as a result, allowing ksmeta here is very easy to code in puppet
	# MAN: (Profiles may inherit from other profiles in lieu of specifing
	# --distro. Inherited profiles will override any settings specified in
	# their parent, with the exception of --ksmeta (templating) and --kopts
	# (kernel options), which will be blended together.)
	# EXAMPLE: If profile A has --kopts="x=7 y=2", B inherits from A, and B
	# has --kopts="x=9 z=2", the actual kernel options that will be used
	# for B are "x=9 y=2 z=2". To remove a kernel argument that may be
	# added by a higher cobbler object (or in the global settings), you can
	# prefix it with a "!".
	$args02 = sprintf("--kopts='%s'", inline_template('<%= kopts.sort.join(" ") %>'))
	$args03 = sprintf("--ksmeta='%s'", inline_template('<%= ksmeta.uniq.sort.join(" ") %>'))

	$args04 = $valid_ipaddress ? {
		'' => '',
		# netmask: cobbler calls this 'subnet'
		default => "--ip-address=${valid_ipaddress} --subnet=${valid_netmask}",
	}

	# TODO: i've allowed specifying gateway even if dhcp==true, is this ok?
	$args05 = $valid_gateway ? {
		'' => '',
		default => "--gateway=${valid_gateway}",
	}

	$args06 = $dhcp ? {
		true => "--static=0",
		default => "--static=1",
	}

	$args07 = $virtcpus ? {
		false => '',
		default => "--virt-cpus=${virtcpus}",	# int
	}

	$args08 = $virtram ? {
		false => '',
		default => "--virt-ram=${virtram}",	# megabytes
	}

	$args09 = $virtpath ? {
		false => '',
		default => "--virt-path=${virtpath}",
	}

	$args10 = $virtfilesize ? {
		false => '',
		default => "--virt-file-size=${virtfilesize}",
	}

	$args11 = $valid_serveroverride ? {
		'' => '',
		# BUG: --server-override is supposed to work, but it seems it's actually '--server'
		#default => "--server-override=${valid_serveroverride}",
		default => "--server=${valid_serveroverride}",
	}

	# put all the args in an array, remove the empty ones, and join with spaces (this removes '  ' double spaces uglyness)
	$arglist = ["${args01}", "${args02}", "${args03}", "${args04}", "${args05}", "${args06}", "${args07}", "${args08}", "${args09}", "${args10}", "${args11}"]
	$args = inline_template('<%= arglist.delete_if {|x| x.empty? }.join(" ") %>')

	$requires = $profile ? {
		'' => undef,	# TODO: can we even allow an empty profile?
		default => Cobbler::Profile[$profile],
	}

	file { "${vardir}/systems/${name}.system":
		content => "${name}\n${args}\n",
		owner => root,
		group => nobody,
		mode => 600,	# u=rw,go=
		notify => Exec["cobbler-systemedit-${name}"],
		# FIXME: add in require => File["${vardir}/systems/"]
		require => $requires,
		ensure => present,
	}

	# NOTE: if cobbler breaks and does a 're-add' of machines, all of these
	# machines will now get their netboot flag set to true! this could be a
	# disaster, because if one of them reboots, it will rebuild! to prevent
	# this, each node can export a cobbler::system::netboot resource, which
	# cobbler collects and uses to ensure it doesn't rebuild a good node...
	# TODO: there needs to be some sort of ttl on old systems that are dead
	# so that the saved exported resource doesn't disable rebuilding a node
	exec { "/usr/bin/cobbler system add --name=${name} ${args} --netboot-enabled=${bool_netboot}":
		logoutput => on_failure,
		unless => "/usr/bin/cobbler system list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if system exists
		# cobbler sync is NOT needed here; thanks to jimi_c in #cobbler
		# < jimi_c> there is no need. It executes what is known as lite-sync to do everything it needs to do
		# < jimi_c> you MAY need to if you're doing dhcpd, depends on if you're doing static leases or not
		#notify => Exec['cobbler-sync'],
		require => [
			File["${vardir}/systems/${name}.system"],
			Package['cobbler'],
		],
		alias => "cobbler-systemadd-${name}",
	}

	# NOTE: editing a machine shouldn't change the: --netboot-enabled flag.
	exec { "/usr/bin/cobbler system edit --name=${name} ${args}":
		refreshonly => true,
		logoutput => on_failure,
		#notify => Exec['cobbler-sync'],	# not needed (see above)
		require => [
			File["${vardir}/systems/${name}.system"],
			Exec["cobbler-systemadd-${name}"],	# require a system add, in case system wasn't made yet
			Package['cobbler'],
		],
		alias => "cobbler-systemedit-${name}",
	}
}

class cobbler_system_netboot_collect {
	# collect to avoid letting a node destruct and rebuild on reboot
	Cobbler::System::Netboot <<| tag == 'cobbler' |>> {
	}
}

# this sets the netboot value of a particular system. this is especially useful
# to export from a configured node. that way, if cobbler is rebuilt, then nodes
# will be able to pre-emptively set their netboot flags, and avoid destruction!
# TODO: what if cobbler gets rebuilt while puppet is off or also being rebuilt?
define cobbler::system::netboot(
	$netboot = false
) {
	$bool_netboot = $netboot ? {
		true => 'true',
		default => 'false',
	}

	$not_bool_netboot = $bool_netboot ? {
		'true' => 'false',
		default => 'true',
	}

	exec { "/usr/bin/cobbler system edit --name=${name} --netboot-enabled=${bool_netboot}":
		logoutput => on_failure,
		unless => "/usr/bin/cobbler system list | /usr/bin/tr -d ' ' | /bin/grep -qxF '${name}' -",	# check to see if system exists
		# flip netbool only if it is in the opposite state of requested
		onlyif => "/usr/bin/cobbler system find --netboot-enabled=${not_bool_netboot} | /bin/grep -qxF '${name}' -",
		require => Cobbler::System["${name}"],	# this should happen first...
		alias => "cobbler-system-netboot-${name}",
	}
}

