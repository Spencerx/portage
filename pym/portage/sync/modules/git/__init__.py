# Copyright 2005-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

"""Scan and generate metadata indexes for binary packages.
"""


module_spec = {
	'name': 'git',
	'description': __doc__,
	'provides':{
		'module1': {
			'name': "git",
			'class': "GitSync",
			'description': __doc__,
			'functions': ['sync',],
			'func_desc': {'sync', 'Performs a git pull on the repo'}
			}
		}
	}
