


class CheckSyncEntries(object):

	def check_repo(repo):
		if repo.sync_type is not None and repo.sync_uri is None:
			writemsg_level("!!! %s\n" % _("Repository '%s' has sync-type attribute, but is missing sync-uri attribute") %
				sname, level=logging.ERROR, noiselevel=-1)
			continue

		if repo.sync_uri is not None and repo.sync_type is None:
			writemsg_level("!!! %s\n" % _("Repository '%s' has sync-uri attribute, but is missing sync-type attribute") %
				sname, level=logging.ERROR, noiselevel=-1)
			continue

		if repo.sync_type not in portage.sync.module_names + [None]:
			writemsg_level("!!! %s\n" % _("Repository '%s' has sync-type attribute set to unsupported value: '%s'") %
				(sname, repo.sync_type), level=logging.ERROR, noiselevel=-1)
			continue

		if repo.sync_type == "cvs" and repo.sync_cvs_repo is None:
			writemsg_level("!!! %s\n" % _("Repository '%s' has sync-type=cvs, but is missing sync-cvs-repo attribute") %
				sname, level=logging.ERROR, noiselevel=-1)
			continue

