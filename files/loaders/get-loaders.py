#!/usr/bin/python

# get the loaders ahead of time so that cobbler can run in an isolated network!
# NOTE: see cobbler/action_dlcontent.py for the list of files it looks for...

import os
import sys
import urlgrabber

force = True
content_server = 'http://cobbler.github.com/loaders'
#dest = '/var/lib/cobbler/loaders'
dest = os.getcwd()
files = (
	("%s/README" % content_server, "%s/README" % dest),
	("%s/COPYING.elilo" % content_server, "%s/COPYING.elilo" % dest),
	("%s/COPYING.yaboot" % content_server, "%s/COPYING.yaboot" % dest),
	("%s/COPYING.syslinux" % content_server, "%s/COPYING.syslinux" % dest),
	("%s/elilo-3.8-ia64.efi" % content_server, "%s/elilo-ia64.efi" % dest),
	("%s/yaboot-1.3.14-12" % content_server, "%s/yaboot" % dest),
	("%s/pxelinux.0-3.61" % content_server, "%s/pxelinux.0" % dest),
	("%s/menu.c32-3.61" % content_server, "%s/menu.c32" % dest),
	("%s/grub-0.97-x86.efi" % content_server, "%s/grub-x86.efi" % dest),
	("%s/grub-0.97-x86_64.efi" % content_server, "%s/grub-x86_64.efi" % dest),
)

print "Script will download to: %s from: %s" % (dest, content_server)
try:
	raw_input('<ENTER>/^C ?')
except KeyboardInterrupt, e:
	sys.exit(1)

for src, dst in files:
	if os.path.exists(dst) and not force:
		print "File: %s already exists." % dst
		continue
	print "Downloading: %s to: %s" % (src, dst)
	urlgrabber.grabber.urlgrab(src, filename=dst)

