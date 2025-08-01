#!/usr/bin/env bash
# Copyright 1999-2025 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# shellcheck disable=SC2128

# Hardcoded bash lists are needed for backward compatibility with
# <portage-2.1.4 since they assume that a newly installed version
# of ebuild.sh will work for pkg_postinst, pkg_prerm, and pkg_postrm
# when portage is upgrading itself.

portage_readonly_metadata=(
	BDEPEND DEFINED_PHASES DESCRIPTION DEPEND EAPI HOMEPAGE INHERITED
	IDEPEND IUSE KEYWORDS LICENSE PDEPEND REQUIRED_USE REPOSITORY RESTRICT
	RDEPEND SRC_URI SLOT
)

portage_readonly_vars=(
	D EBUILD_PHASE_FUNC EBUILD_SH_ARGS EBUILD_PHASE EMERGE_FROM EBUILD
	EROOT ED FILESDIR MERGE_TYPE PORTAGE_EBUILD_EXTRA_SOURCE
	PORTAGE_EBUILD_EXIT_FILE PORTAGE_ECLASS_LOCATIONS
	PORTAGE_EXPLICIT_INHERIT PORTAGE_OVERRIDE_EPREFIX
	PORTAGE_BINPKG_TAR_OPTS PORTAGE_INTERNAL_CALLER PORTAGE_ACTUAL_DISTDIR
	PORTAGE_BINPKG_TMPFILE PORTAGE_XATTR_EXCLUDE PORTAGE_REPOSITORIES
	PORTAGE_WORKDIR_MODE PORTAGE_BINPKG_FILE PORTAGE_BUILD_GROUP
	PORTAGE_DEPCACHEDIR PM_EBUILD_HOOK_DIR PORTAGE_BUILD_USER
	PORTAGE_CONFIGROOT PORTAGE_IPC_DAEMON PORTAGE_PROPERTIES
	PORTAGE_PYTHONPATH PORTAGE_UPDATE_ENV PORTAGE_REPO_NAME
	PORTAGE_ARCHLIST PORTAGE_BIN_PATH PORTAGE_BUILDDIR PORTAGE_COLORMAP
	PORTAGE_INST_GID PORTAGE_INST_UID PORTAGE_LOG_FILE PORTAGE_PYM_PATH
	PORTAGE_RESTRICT PORTAGE_USERNAME PORTAGE_GRPNAME PORTAGE_VERBOSE
	PORTAGE_BASHRC PORTAGE_PYTHON PORTAGE_TMPDIR PORTAGE_DEBUG PORTAGE_IUSE
	PORTAGE_GID REPLACED_BY_VERSION REPLACING_VERSIONS T WORKDIR
	__PORTAGE_TEST_HARDLINK_LOCKS __PORTAGE_HELPER
	portage_mutable_filtered_vars portage_saved_readonly_vars
	portage_readonly_metadata portage_readonly_vars
)

portage_saved_readonly_vars=(
	A CATEGORY PVR PF PN PR PV P
)

# Variables that portage sets but doesn't mark readonly.
# In order to prevent changed values from causing unexpected
# interference, they are filtered out of the environment when
# it is saved or loaded (any mutations do not persist).
portage_mutable_filtered_vars=( AA HOSTNAME )

# @FUNCTION: __filter_readonly_variables
# @DESCRIPTION: [--filter-sandbox] [--allow-extra-vars]
# Read an environment from stdin and echo to stdout while filtering variables
# with names that are known to cause interference:
#
#   * all variables that can be set by or that affect bash (except EMACS & PATH)
#   * some specific variables that affect portage or sandbox behavior
#   * variable names that begin with a digit or that contain any
#     non-alphanumeric characters that are not be supported by bash
#
# --filter-sandbox causes all SANDBOX_* variables to be filtered, which
# is only desired in certain cases, such as during preprocessing or when
# saving environment.bz2 for a binary or installed package.
#
# --filter-features causes the special FEATURES variable to be filtered.
# Generally, we want it to persist between phases since the user might
# want to modify it via bashrc to enable things like splitdebug and
# installsources for specific packages. They should be able to modify it
# in pre_pkg_setup() and have it persist all the way through the install
# phase. However, if FEATURES exist inside environment.bz2 then they
# should be overridden by current settings.
#
# --filter-locale causes locale related variables such as LANG and LC_*
# variables to be filtered. These variables should persist between phases,
# in case they are modified by the ebuild. However, the current user
# settings should be used when loading the environment from a binary or
# installed package.
#
# --filter-path causes the PATH variable to be filtered. This variable
# should persist between phases, in case it is modified by the ebuild.
# However, old settings should be overridden when loading the
# environment from a binary or installed package.
#
# --allow-extra-vars inhibits the filtering of the variables whose names are
# specified by the PORTAGE_SAVED_READONLY_VARS and PORTAGE_MUTABLE_FILTERED_VARS
# variables. However, in the absence of the option, only the CATEGORY, P, PF,
# PN, PR, PV and PVR variables shall be filtered, provided that the value of
# EMERGE_FROM is equal to "binary". The reason for this exception in behaviour
# is to preserve various variables as they were at the time that the binary
# package was built while protecting against the application of package renames.
__filter_readonly_variables() {
	local -a filtered_vars bash_vars
	local IFS

	# Collect an initial list of special bash variables by instructing a
	# hygienic instance of bash(1) to report them.
	mapfile -t bash_vars < <(
		# Like compgen -A variable but doesn't require readline support.
		env -i -- "${BASH}" -c "printf %s\\\n $(printf '${!%s*} ' {A..Z} {a..z} _)" \
		| grep -vx PATH
	)
	# Incorporate other variables that are known to either be set by or be
	# able to influence bash. This list was last updated for bash-5.3.
	bash_vars+=(
		BASH_LOADABLES_PATH BASH_XTRACEFD BASH_REMATCH BASH_TRAPSIG
		BASH_COMPAT BASH_ENV COMP_CWORD COMP_POINT COMP_WORDS CHILD_MAX
		COMPREPLY COMP_LINE COMP_TYPE COMP_KEY COLUMNS CDPATH COPROC
		EXECIGNORE ENV FUNCNAME FUNCNEST FIGNORE FCEDIT GLOBIGNORE
		GLOBSORT HISTTIMEFORMAT HISTFILESIZE HISTCONTROL HISTIGNORE
		HISTFILE HISTSIZE HOSTFILE HOME INSIDE_EMACS IGNOREEOF INPUTRC
		LINES MAILCHECK MAILPATH MAPFILE MAIL OLDPWD OPTARG
		POSIXLY_CORRECT PROMPT_COMMAND PROMPT_DIRTRIM PIPESTATUS PS0
		PS1 PS2 PS3 READLINE_ARGUMENT READLINE_POINT READLINE_LINE
		READLINE_MARK REPLY TIMEFORMAT TMPDIR TMOUT auto_resume
		histchars

		# Exported functions bear this prefix.
		"BASH_FUNC_.*"
	)
	filtered_vars+=(
		"${portage_readonly_vars[@]}"
		_portage_filter_opts
		"${bash_vars[@]}"
		"___.*"
	)

	# Filter SYSROOT unconditionally. It is propagated in every EAPI
	# because it was used unofficially before EAPI 7. See bug #661006.
	filtered_vars+=( SYSROOT )

	if ___eapi_has_BROOT; then
		filtered_vars+=( BROOT )
	fi
	# Don't filter/interfere with prefix variables unless they are
	# supported by the current EAPI.
	if ___eapi_has_prefix_variables; then
		filtered_vars+=( ED EPREFIX EROOT )
		if ___eapi_has_SYSROOT; then
			filtered_vars+=( ESYSROOT )
		fi
	fi
	if ___eapi_has_PORTDIR_ECLASSDIR; then
		filtered_vars+=( PORTDIR ECLASSDIR )
	fi

	if has --filter-sandbox "$@"; then
		filtered_vars+=( "SANDBOX_.*" )
	else
		filtered_vars+=(
			SANDBOX_DEBUG_LOG SANDBOX_DISABLED SANDBOX_ACTIVE
			SANDBOX_BASHRC SANDBOX_LIB SANDBOX_LOG SANDBOX_ON
		)
	fi
	if has --filter-features "$@"; then
		filtered_vars+=( FEATURES PORTAGE_FEATURES )
	fi
	if has --filter-path "$@"; then
		filtered_vars+=( PATH )
	fi
	if has --filter-locale "$@"; then
		filtered_vars+=(
			LC_MESSAGES LC_MONETARY LC_COLLATE LC_NUMERIC LC_CTYPE
			LC_PAPER LC_TIME LC_ALL LANG
		)
	fi
	if has --allow-extra-vars "$@"; then
		:
	elif [[ "${EMERGE_FROM}" = binary ]]; then
		# Preserve additional variables from build time, while
		# excluding some variables that are untrusted, due to the
		# possible application of package renames to binpkgs.
		filtered_vars+=( CATEGORY PVR PF PN PR PV P )
	else
		# Allow for the option to have its full effect.
		filtered_vars+=(
			"${portage_mutable_filtered_vars[@]}"
			"${portage_saved_readonly_vars[@]}"
		)
	fi

	"${PORTAGE_PYTHON:-/usr/bin/python}" "${PORTAGE_BIN_PATH}"/filter-bash-environment.py "${filtered_vars[*]}" \
	|| die "filter-bash-environment.py failed"
}

# @FUNCTION: __preprocess_ebuild_env
# @DESCRIPTION:
# Filter any readonly variables from ${T}/environment, source it, and then
# save it via __save_ebuild_env(). This process should be sufficient to prevent
# any stale variables or functions from an arbitrary environment from
# interfering with the current environment. This is useful when an existing
# environment needs to be loaded from a binary or installed package.
__preprocess_ebuild_env() {
	local _portage_filter_opts="--filter-features --filter-locale --filter-path --filter-sandbox"

	# If environment.raw is present, this is a signal from the python side,
	# indicating that the environment may contain stale FEATURES and
	# SANDBOX_{DENY,PREDICT,READ,WRITE} variables that should be filtered out.
	# Otherwise, we don't need to filter the environment.
	[[ -f "${T}/environment.raw" ]] || return 0

	__filter_readonly_variables ${_portage_filter_opts} < "${T}"/environment \
		>> "${T}/environment.filtered" || return $?

	unset _portage_filter_opts
	mv "${T}"/environment.filtered "${T}"/environment || return $?
	rm -f "${T}/environment.success" || return $?

	# WARNING: Code inside this subshell should avoid making assumptions
	# about variables or functions after source "${T}"/environment has been
	# called. Any variables that need to be relied upon should already be
	# filtered out above.
	(
		export SANDBOX_ON=1
		source "${T}/environment" || exit $?
		# We have to temporarily disable sandbox since the
		# SANDBOX_{DENY,READ,PREDICT,WRITE} values we've just loaded
		# may be unusable (triggering in spurious sandbox violations)
		# until we've merged them with our current values.
		export SANDBOX_ON=0

		# It's remotely possible that __save_ebuild_env() has been overridden
		# by the above source command. To protect ourselves, we override it
		# here with our own version. ${PORTAGE_BIN_PATH} is safe to use here
		# because it's already filtered above.
		source "${PORTAGE_BIN_PATH}/save-ebuild-env.sh" || exit $?

		# Prefer latest make.conf values of these.
		unset PORTAGE_BZIP2_COMMAND PORTAGE_BUNZIP2_COMMAND

		# Rely on __save_ebuild_env() to filter out any remaining variables
		# and functions that could interfere with the current environment.
		__save_ebuild_env || exit $?
		: >> "${T}/environment.success" || exit $?
	) > "${T}/environment.filtered"

	local retval
	if [[ -e "${T}/environment.success" ]]; then
		__filter_readonly_variables --filter-features < \
			"${T}/environment.filtered" > "${T}/environment"
		retval=$?
	else
		retval=1
	fi

	rm -f "${T}"/environment.{filtered,raw,success}
	return ${retval}
}

__ebuild_phase() {
	local __EBEGIN_EEND_COUNT=0

	declare -F "$1" >/dev/null && __qa_call $1
	if (( __EBEGIN_EEND_COUNT > 0 )); then
		eqawarn "QA Notice: ebegin called without eend in $1"
	fi
}

__ebuild_phase_with_hooks() {
	local x phase_name=${1}
	for x in {pre_,,post_}${phase_name} ; do
		__ebuild_phase ${x}
	done
}

__dyn_pretend() {
	if [[ -e ${PORTAGE_BUILDDIR}/.pretended ]] ; then
		__vecho ">>> It appears that '${PF}' is already pretended; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.pretended' to force pretend."
		return 0
	fi

	__ebuild_phase pre_pkg_pretend
	__ebuild_phase pkg_pretend
	: >> "${PORTAGE_BUILDDIR}/.pretended" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.pretended"
	__ebuild_phase post_pkg_pretend
}

__dyn_setup() {
	if [[ -e ${PORTAGE_BUILDDIR}/.setuped ]] ; then
		__vecho ">>> It appears that '${PF}' is already setup; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.setuped' to force setup."
		return 0
	fi

	__ebuild_phase pre_pkg_setup
	__ebuild_phase pkg_setup
	: >> "${PORTAGE_BUILDDIR}/.setuped" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.setuped"
	__ebuild_phase post_pkg_setup
}

__dyn_unpack() {
	if [[ -f ${PORTAGE_BUILDDIR}/.unpacked ]] ; then
		__vecho ">>> WORKDIR is up-to-date, keeping..."
		return 0
	fi

	if [[ ! -d "${WORKDIR}" ]]; then
		install -m${PORTAGE_WORKDIR_MODE:-0700} -d "${WORKDIR}" || die "Failed to create dir '${WORKDIR}'"
	fi

	cd "${WORKDIR}" || die "Directory change failed: \`cd '${WORKDIR}'\`"
	__ebuild_phase pre_src_unpack
	__vecho ">>> Unpacking source..."
	__ebuild_phase src_unpack
	: >> "${PORTAGE_BUILDDIR}/.unpacked" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.unpacked"
	__vecho ">>> Source unpacked in ${WORKDIR}"
	__ebuild_phase post_src_unpack
}

__dyn_clean() {
	if [[ -z "${PORTAGE_BUILDDIR}" ]]; then
		echo "Aborting clean phase because PORTAGE_BUILDDIR is unset!"
		return 1
	elif [[ ! -d "${PORTAGE_BUILDDIR}" ]]; then
		return 0
	fi

	if contains_word chflags "${FEATURES}"; then
		chflags -R noschg,nouchg,nosappnd,nouappnd "${PORTAGE_BUILDDIR}"
		chflags -R nosunlnk,nouunlnk "${PORTAGE_BUILDDIR}" 2>/dev/null
	fi

	# Some kernels, such as Solaris, return EINVAL when an attempt
	# is made to remove the current working directory.
	cd "${PORTAGE_PYM_PATH}" || \
		die "PORTAGE_PYM_PATH does not exist: '${PORTAGE_PYM_PATH}'"

	rm -rf "${PORTAGE_BUILDDIR}/image" "${PORTAGE_BUILDDIR}/homedir" \
		"${PORTAGE_BUILDDIR}/empty"
	rm -f "${PORTAGE_BUILDDIR}/.installed"

	if [[ ${EMERGE_FROM} = binary ]] \
		|| ! contains_word keeptemp "${FEATURES}" \
		&& ! contains_word keepwork "${FEATURES}"
	then
		rm -rf "${T}"
	fi

	if [[ ${EMERGE_FROM} = binary ]] || ! contains_word keepwork "${FEATURES}"; then
		rm -f "${PORTAGE_BUILDDIR}"/.{ebuild_changed,logid,pretended,setuped,unpacked,prepared} \
			"${PORTAGE_BUILDDIR}"/.{configured,compiled,tested,packaged,instprepped} \
			"${PORTAGE_BUILDDIR}"/.die_hooks \
			"${PORTAGE_BUILDDIR}"/.exit_status

		rm -rf "${PORTAGE_BUILDDIR}/build-info" \
			"${PORTAGE_BUILDDIR}/.ipc"
		rm -rf "${WORKDIR}"
		rm -f "${PORTAGE_BUILDDIR}/files"
	fi

	if [[ -f "${PORTAGE_BUILDDIR}/.unpacked" ]]; then
		printf '%s\0' "${PORTAGE_BUILDDIR}" \
		| find0 -depth -type d -empty -print0 \
		| while read -rd ''; do [[ ${REPLY} != "${WORKDIR}"?(/*) ]] && printf '%s\0' "${REPLY}"; done \
		| ${XARGS:?} -0 rmdir --
	fi

	# Do not bind this to doebuild defined DISTDIR; don't trust doebuild, and if mistakes are made it'll
	# result in it wiping the users distfiles directory (bad).
	rm -rf "${PORTAGE_BUILDDIR}/distdir"

	printf '%s\0' "${PORTAGE_BUILDDIR}" \
	| find0 -maxdepth 0 -type d -empty -exec rmdir -- {} \;
}

__abort_handler() {
	local msg
	if [[ "$2" != "fail" ]]; then
		msg="${EBUILD}: ${1} aborted; exiting."
	else
		msg="${EBUILD}: ${1} failed; exiting."
	fi
	echo
	echo "${msg}"
	echo
	eval ${3}

	# Unset signal handler
	trap - SIGINT SIGQUIT
}

__abort_prepare() {
	__abort_handler src_prepare $1
	rm -f "${PORTAGE_BUILDDIR}/.prepared"
	exit 1
}

__abort_configure() {
	__abort_handler src_configure $1
	rm -f "${PORTAGE_BUILDDIR}/.configured"
	exit 1
}

__abort_compile() {
	__abort_handler "src_compile" $1
	rm -f "${PORTAGE_BUILDDIR}/.compiled"
	exit 1
}

__abort_test() {
	__abort_handler "__dyn_test" $1
	rm -f "${PORTAGE_BUILDDIR}/.tested"
	exit 1
}

__abort_install() {
	__abort_handler "src_install" $1
	rm -rf "${PORTAGE_BUILDDIR}/image"
	exit 1
}

__has_phase_defined_up_to() {
	local phase
	for phase in unpack prepare configure compile test install; do
		contains_word "${phase}" "${DEFINED_PHASES}" && return 0
		[[ ${phase} == $1 ]] && return 1
	done
	# We shouldn't actually get here
	return 1
}

__dyn_prepare() {

	if [[ -e ${PORTAGE_BUILDDIR}/.prepared ]] ; then
		__vecho ">>> It appears that '${PF}' is already prepared; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.prepared' to force prepare."
		return 0
	fi

	if [[ -d ${S} ]] ; then
		cd "${S}"
	elif ___eapi_has_S_WORKDIR_fallback; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! __has_phase_defined_up_to prepare; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap __abort_prepare SIGINT SIGQUIT

	__ebuild_phase pre_src_prepare
	__vecho ">>> Preparing source in ${PWD} ..."
	__ebuild_phase src_prepare

	# keep path in eapply_user in sync!
	if ___eapi_has_eapply_user && [[ ! -f ${T}/.portage_user_patches_applied ]]; then
		die "eapply_user (or default) must be called in src_prepare()!"
	fi

	: >> "${PORTAGE_BUILDDIR}/.prepared" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.prepared"
	__vecho ">>> Source prepared."
	__ebuild_phase post_src_prepare

	trap - SIGINT SIGQUIT
}

__dyn_configure() {
	if [[ -e ${PORTAGE_BUILDDIR}/.configured ]] ; then
		__vecho ">>> It appears that '${PF}' is already configured; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.configured' to force configuration."
		return 0
	fi

	if [[ -d ${S} ]] ; then
		cd "${S}"
	elif ___eapi_has_S_WORKDIR_fallback; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! __has_phase_defined_up_to configure; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap __abort_configure SIGINT SIGQUIT

	__ebuild_phase pre_src_configure

	__vecho ">>> Configuring source in ${PWD} ..."
	__ebuild_phase src_configure
	: >> "${PORTAGE_BUILDDIR}/.configured" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.configured"
	__vecho ">>> Source configured."

	__ebuild_phase post_src_configure

	trap - SIGINT SIGQUIT
}

__dyn_compile() {
	if [[ -e ${PORTAGE_BUILDDIR}/.compiled ]] ; then
		__vecho ">>> It appears that '${PF}' is already compiled; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.compiled' to force compilation."
		return 0
	fi

	if [[ -d ${S} ]] ; then
		cd "${S}"
	elif ___eapi_has_S_WORKDIR_fallback; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! __has_phase_defined_up_to compile; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	trap __abort_compile SIGINT SIGQUIT

	__ebuild_phase pre_src_compile

	__vecho ">>> Compiling source in ${PWD} ..."
	__ebuild_phase src_compile
	: >> "${PORTAGE_BUILDDIR}/.compiled" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.compiled"
	__vecho ">>> Source compiled."

	__ebuild_phase post_src_compile

	trap - SIGINT SIGQUIT
}

__dyn_test() {
	if [[ -e ${PORTAGE_BUILDDIR}/.tested ]] ; then
		__vecho ">>> It appears that ${PN} has already been tested; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.tested' to force test."
		return
	fi

	trap "__abort_test" SIGINT SIGQUIT

	if [[ -d ${S} ]]; then
		cd "${S}"
	elif ___eapi_has_S_WORKDIR_fallback; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! __has_phase_defined_up_to test; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	if contains_word test "${PORTAGE_RESTRICT}" \
		&& ! contains_word all "${ALLOW_TEST}" \
		&& ! { contains_word test_network "${PORTAGE_PROPERTIES}" && contains_word network "${ALLOW_TEST}"; } \
		&& ! { contains_word test_privileged "${PORTAGE_PROPERTIES}" && contains_word privileged "${ALLOW_TEST}"; }
	then
		einfo "Skipping make test/check due to ebuild restriction."
		__vecho ">>> Test phase [disabled because of RESTRICT=test]: ${CATEGORY}/${PF}"

	# If ${EBUILD_FORCE_TEST} == 1 and FEATURES came from ${T}/environment
	# then it might not have FEATURES=test like it's supposed to here.
	elif [[ ${EBUILD_FORCE_TEST} != 1 ]] && ! contains_word test "${FEATURES}"; then
		__vecho ">>> Test phase [not enabled]: ${CATEGORY}/${PF}"
	else
		local save_sp=${SANDBOX_PREDICT}
		addpredict /
		__ebuild_phase pre_src_test

		__vecho ">>> Test phase: ${CATEGORY}/${PF}"
		__ebuild_phase src_test
		__vecho ">>> Completed testing ${CATEGORY}/${PF}"

		: >> "${PORTAGE_BUILDDIR}/.tested" || \
			die "Failed to create ${PORTAGE_BUILDDIR}/.tested"
		__ebuild_phase post_src_test
		SANDBOX_PREDICT=${save_sp}
	fi

	trap - SIGINT SIGQUIT
}

__dyn_install() {
	[[ -z "${PORTAGE_BUILDDIR}" ]] && die "${FUNCNAME}: PORTAGE_BUILDDIR is unset"

	if contains_word noauto "${FEATURES}"; then
		rm -f "${PORTAGE_BUILDDIR}/.installed"
	elif [[ -e ${PORTAGE_BUILDDIR}/.installed ]] ; then
		__vecho ">>> It appears that '${PF}' is already installed; skipping."
		__vecho ">>> Remove '${PORTAGE_BUILDDIR}/.installed' to force install."
		return 0
	fi
	trap "__abort_install" SIGINT SIGQUIT

	# Handle setting QA_* based on QA_PREBUILT
	# Those variables shouldn't be needed before src_install()
	# (QA_PRESTRIPPED is used in prepstrip, others in install-qa-checks)
	# and delay in setting them allows us to set them in pkg_setup()
	if [[ -n ${QA_PREBUILT} ]] ; then
		# These ones support fnmatch patterns
		QA_EXECSTACK+=" ${QA_PREBUILT}"
		QA_TEXTRELS+=" ${QA_PREBUILT}"
		QA_WX_LOAD+=" ${QA_PREBUILT}"

		# These ones support regular expressions, so translate
		# fnmatch patterns to regular expressions
		for x in QA_DT_NEEDED QA_FLAGS_IGNORED QA_PRESTRIPPED \
			QA_SONAME QA_SONAME_NO_SYMLINK; do
			if [[ ${!x@a} == *a* ]]; then
				eval "${x}=(\"\${${x}[@]}\" ${QA_PREBUILT//\*/.*})"
			else
				eval "${x}+=\" ${QA_PREBUILT//\*/.*}\""
			fi
		done

		unset x
	fi

	# This needs to be exported since prepstrip is a separate shell script.
	[[ -n ${QA_PRESTRIPPED} ]] && export QA_PRESTRIPPED
	eval "[[ -n \${QA_PRESTRIPPED_${ARCH/-/_}} ]] && \
		export QA_PRESTRIPPED_${ARCH/-/_}"

	__ebuild_phase pre_src_install

	if ___eapi_has_prefix_variables; then
		_x=${ED}
	else
		_x=${D}
	fi
	rm -rf "${D}"
	mkdir -p "${_x}"
	unset _x

	if [[ -d ${S} ]] ; then
		cd "${S}"
	elif ___eapi_has_S_WORKDIR_fallback; then
		cd "${WORKDIR}"
	elif [[ -z ${A} ]] && ! __has_phase_defined_up_to install; then
		cd "${WORKDIR}"
	else
		die "The source directory '${S}' doesn't exist"
	fi

	__vecho
	__vecho ">>> Install ${CATEGORY}/${PF} into ${D}"

	# Reset exeinto(), docinto(), insinto(), and into() state variables
	# in case the user is running the install phase multiple times
	# consecutively via the ebuild command.
	if ___eapi_has_DESTTREE_INSDESTTREE; then
		export DESTTREE=/usr
		export INSDESTTREE=""
	else
		export __E_DESTTREE=/usr
		export __E_INSDESTTREE=""
	fi
	export __E_EXEDESTTREE=""
	export __E_DOCDESTTREE=""

	__ebuild_phase src_install
	: >> "${PORTAGE_BUILDDIR}/.installed" || \
		die "Failed to create ${PORTAGE_BUILDDIR}/.installed"
	__vecho ">>> Completed installing ${CATEGORY}/${PF} into ${D}"
	__vecho
	__ebuild_phase post_src_install

	# Record the sizes of WORKDIR and D to the build log. Employ a subshell
	# so as to avoid polluting the caller's environment with several helper
	# functions.
	(
		hash du 2>/dev/null || exit 0

		local nsz isz

		nsz=$(du -ks "${WORKDIR}")
		isz=$(du -ks "${D}")
		nsz=${nsz%%[[:blank:]]*}
		isz=${isz%%[[:blank:]]*}

		# align $1 to the right to the width of the widest of $1 and $2
		padl() {
			local s1=$1
			local s2=$2
			local width=${#s1}
			[[ ${#s2} -gt ${width} ]] && width=${#s2}
			printf "%*s" ${width} "${s1}"
		}

		# transform number in KiB into MiB, GiB or TiB based on size
		human() {
			local s1=$1
			local units=( KiB MiB GiB TiB )

			s1=$((s1 * 10))
			while [[ ${s1} -gt 10240 && ${#units[@]} -gt 1 ]] ; do
				s1=$((s1 / 1024 ))
				units=( ${units[@]:1} )
			done

			local r=${s1: -1}
			s1=$((s1 / 10))
			printf "%s.%s %s" "${s1}" "${r}" "${units[0]}"
		}

		size() {
			local s1=$1
			local s2=$2
			local out="$(padl "${s1}" "${s2}") KiB"

			if [[ ${s1} -gt 1024 ]] ; then
				s1=$(human ${s1})
				if [[ ${s2} -gt 1024 ]] ; then
					s2=$(human ${s2})
					s1=$(padl "${s1}" "${s2}")
				fi
				out+=" (${s1})"
			fi
			echo "${out}"
		}
		einfo "Final size of build directory: $(size "${nsz}" "${isz}")"
		einfo "Final size of installed tree:  $(size "${isz}" "${nsz}")"
	)
	__vecho

	cd "${PORTAGE_BUILDDIR}"/build-info
	set -f
	local f x

	IFS=$' \t\n\r'
	for f in CATEGORY DEFINED_PHASES FEATURES INHERITED IUSE \
		PF PKGUSE SLOT KEYWORDS HOMEPAGE DESCRIPTION \
		ASFLAGS CBUILD CC CFLAGS CHOST CTARGET CXX \
		CXXFLAGS EXTRA_ECONF EXTRA_EINSTALL EXTRA_MAKE \
		LDFLAGS LIBCFLAGS LIBCXXFLAGS QA_CONFIGURE_OPTIONS \
		QA_DESKTOP_FILE QA_PREBUILT PROVIDES_EXCLUDE REQUIRES_EXCLUDE \
		PKG_INSTALL_MASK; do

		x=$(echo -n ${!f})
		[[ -n ${x} ]] && echo "${x}" > ${f}
	done
	# whitespace preserved
	for f in QA_AM_MAINTAINER_MODE ; do
		[[ -n ${!f} ]] && echo "${!f}" > ${f}
	done
	echo "${USE}"       > USE
	echo "${EAPI:-0}"   > EAPI

	# Save EPREFIX, since it makes it easy to use chpathtool to
	# adjust the content of a binary package so that it will
	# work in a different EPREFIX from the one is was built for.
	if ___eapi_has_prefix_variables && [[ -n ${EPREFIX} ]]; then
		echo "${EPREFIX}" > EPREFIX
	fi

	set +f

	# local variables can leak into the saved environment.
	unset f

	# Use safe cwd, avoiding unsafe import for bug #469338.
	cd "${PORTAGE_PYM_PATH}"
	__save_ebuild_env --exclude-init-phases | __filter_readonly_variables \
		--filter-path --filter-sandbox --allow-extra-vars > \
		"${PORTAGE_BUILDDIR}"/build-info/environment
	assert "__save_ebuild_env failed"
	cd "${PORTAGE_BUILDDIR}"/build-info || die

	${PORTAGE_BZIP2_COMMAND} -f9 environment

	cp "${EBUILD}" "${PF}.ebuild"
	[[ -n "${PORTAGE_REPO_NAME}" ]]  && echo "${PORTAGE_REPO_NAME}" > repository
	[[ -n ${PORTAGE_REPO_REVISIONS} ]] && echo "${PORTAGE_REPO_REVISIONS}" > REPO_REVISIONS
	if contains_word nostrip "${FEATURES} ${PORTAGE_RESTRICT}" || contains_word strip "${PORTAGE_RESTRICT}"; then
		: >> DEBUGBUILD
	fi
	trap - SIGINT SIGQUIT
}

__dyn_help() {
	echo
	echo "Portage"
	echo "Copyright 1999-2022 Gentoo Authors"
	echo
	echo "How to use the ebuild command:"
	echo
	echo "The first argument to ebuild should be an existing .ebuild file."
	echo
	echo "One or more of the following options can then be specified.  If more"
	echo "than one option is specified, each will be executed in order."
	echo
	echo "  help        : show this help screen"
	echo "  pretend     : execute package specific pretend actions"
	echo "  setup       : execute package specific setup actions"
	echo "  fetch       : download source archive(s) and patches"
	echo "  nofetch     : display special fetch instructions"
	echo "  digest      : create a manifest file for the package"
	echo "  manifest    : create a manifest file for the package"
	echo "  unpack      : unpack sources (auto-dependencies if needed)"
	echo "  prepare     : prepare sources (auto-dependencies if needed)"
	echo "  configure   : configure sources (auto-fetch/unpack if needed)"
	echo "  compile     : compile sources (auto-fetch/unpack/configure if needed)"
	echo "  test        : test package (auto-fetch/unpack/configure/compile if needed)"
	echo "  preinst     : execute pre-install instructions"
	echo "  postinst    : execute post-install instructions"
	echo "  install     : install the package to the temporary install directory"
	echo "  qmerge      : merge image into live filesystem, recording files in db"
	echo "  merge       : do fetch, unpack, compile, install and qmerge"
	echo "  prerm       : execute pre-removal instructions"
	echo "  postrm      : execute post-removal instructions"
	echo "  unmerge     : remove package from live filesystem"
	echo "  config      : execute package specific configuration actions"
	echo "  package     : create a tarball package in ${PKGDIR}/All"
	echo "  rpm         : build a RedHat RPM package"
	echo "  clean       : clean up all source and temporary files"
	echo
	echo "The following settings will be used for the ebuild process:"
	echo
	echo "  package     : ${PF}"
	echo "  slot        : ${SLOT}"
	echo "  category    : ${CATEGORY}"
	echo "  description : ${DESCRIPTION}"
	echo "  system      : ${CHOST}"
	echo "  C flags     : ${CFLAGS}"
	echo "  C++ flags   : ${CXXFLAGS}"
	echo "  make flags  : ${MAKEOPTS}"
	echo -n "  build mode  : "
	if contains_word nostrip "${FEATURES} ${PORTAGE_RESTRICT}" || contains_word strip "${PORTAGE_RESTRICT}"; then
		echo "debug (large)"
	else
		echo "production (stripped)"
	fi
	echo "  merge to    : ${ROOT}"
	echo
	if [[ -n "${USE}" ]]; then
		echo "Additionally, support for the following optional features will be enabled:"
		echo
		echo "  ${USE}"
	fi
	echo
}

# @FUNCTION: __ebuild_arg_to_phase
# @DESCRIPTION:
# Translate a known ebuild(1) argument into the precise
# name of it's corresponding ebuild phase.
__ebuild_arg_to_phase() {
	[[ $# -ne 1 ]] && die "expected exactly 1 arg, got $#: $*"
	local arg=$1
	local phase_func=""

	case "${arg}" in
		pretend)
			___eapi_has_pkg_pretend && \
				phase_func=pkg_pretend
			;;
		setup)
			phase_func=pkg_setup
			;;
		nofetch)
			phase_func=pkg_nofetch
			;;
		unpack)
			phase_func=src_unpack
			;;
		prepare)
			___eapi_has_src_prepare && \
				phase_func=src_prepare
			;;
		configure)
			___eapi_has_src_configure && \
				phase_func=src_configure
			;;
		compile)
			phase_func=src_compile
			;;
		test)
			phase_func=src_test
			;;
		install)
			phase_func=src_install
			;;
		preinst)
			phase_func=pkg_preinst
			;;
		postinst)
			phase_func=pkg_postinst
			;;
		prerm)
			phase_func=pkg_prerm
			;;
		postrm)
			phase_func=pkg_postrm
			;;
	esac

	[[ -z ${phase_func} ]] && return 1
	echo "${phase_func}"
	return 0
}

__ebuild_phase_funcs() {
	[[ $# -ne 2 ]] && die "expected exactly 2 args, got $#: $*"

	local eapi=$1
	local phase_func=$2
	local all_phases="src_compile pkg_config src_configure pkg_info
		src_install pkg_nofetch pkg_postinst pkg_postrm pkg_preinst
		src_prepare pkg_prerm pkg_pretend pkg_setup src_test src_unpack"
	local x

	# First, set up the error handlers for default*
	for x in ${all_phases} ; do
		eval "default_${x}() {
			die \"default_${x}() is not supported in EAPI='${eapi}' in phase ${phase_func}\"
		}"
	done

	# We can just call the specific handler -- it will either error out
	# on invalid phase or run it.
	eval "default() {
		default_${phase_func}
	}"

	case "${eapi}" in
		0|1) # EAPIs not supporting 'default'

			for x in pkg_nofetch src_unpack src_test ; do
				declare -F ${x} >/dev/null || \
					eval "$x() { __eapi0_${x}; }"
			done

			if ! declare -F src_compile >/dev/null ; then
				case "${eapi}" in
					0)
						src_compile() { __eapi0_src_compile; }
						;;
					*)
						src_compile() { __eapi1_src_compile; }
						;;
				esac
			fi
			;;

		*) # EAPIs supporting 'default'

			# defaults starting with EAPI 0
			[[ ${phase_func} == pkg_nofetch ]] && \
				default_pkg_nofetch() { __eapi0_pkg_nofetch; }
			[[ ${phase_func} == src_unpack ]] && \
				default_src_unpack() { __eapi0_src_unpack; }
			[[ ${phase_func} == src_test ]] && \
				default_src_test() { __eapi0_src_test; }

			# defaults starting with EAPI 2
			[[ ${phase_func} == src_prepare ]] && \
				default_src_prepare() { __eapi2_src_prepare; }
			[[ ${phase_func} == src_configure ]] && \
				default_src_configure() { __eapi2_src_configure; }
			[[ ${phase_func} == src_compile ]] && \
				default_src_compile() { __eapi2_src_compile; }

			# bind supported phases to the defaults
			declare -F pkg_nofetch >/dev/null || \
				pkg_nofetch() { default; }
			declare -F src_unpack >/dev/null || \
				src_unpack() { default; }
			declare -F src_prepare >/dev/null || \
				src_prepare() { default; }
			declare -F src_configure >/dev/null || \
				src_configure() { default; }
			declare -F src_compile >/dev/null || \
				src_compile() { default; }
			declare -F src_test >/dev/null || \
				src_test() { default; }

			# defaults starting with EAPI 4
			if [[ ${eapi} != [23] ]]; then
				[[ ${phase_func} == src_install ]] && \
					default_src_install() { __eapi4_src_install; }

				declare -F src_install >/dev/null || \
					src_install() { default; }
			fi

			# defaults starting with EAPI 6
			if [[ ${eapi} != [2-5] ]]; then
				[[ ${phase_func} == src_prepare ]] && \
					default_src_prepare() { __eapi6_src_prepare; }
				[[ ${phase_func} == src_install ]] && \
					default_src_install() { __eapi6_src_install; }

				declare -F src_prepare >/dev/null || \
					src_prepare() { default; }
			fi

			# defaults starting with EAPI 8
			if [[ ${eapi} != [2-7] ]]; then
				[[ ${phase_func} == src_prepare ]] && \
					default_src_prepare() { __eapi8_src_prepare; }
			fi
			;;
	esac
}

__ebuild_main() {
	# Subshell/helper die support (must export for the die helper).
	# Since this function is typically executed in a subshell,
	# setup EBUILD_MASTER_PID to refer to the current ${BASHPID},
	# which seems to give the best results when further
	# nested subshells call die.
	export EBUILD_MASTER_PID=${BASHPID}
	trap 'exit 1' SIGTERM

	if [[ -v PORTAGE_EBUILD_EXTRA_SOURCE &&
			  ${PORTAGE_EBUILD_EXTRA_SOURCE} != ${T}/* ]]; then
		# Cleanup PORTAGE_EBUILD_EXTRA_SOURCE after ebuild.sh
		# (__ebuild_main()) finishes if PORTAGE_EBUILD_EXTRA_SOURCE is
		# not under T.
		__portage_ebuild_exit() {
			rm "${PORTAGE_EBUILD_EXTRA_SOURCE}" ||
				die "failed to remove PORTAGE_EBUILD_EXTRA_SOURCE file (${PORTAGE_EBUILD_EXTRA_SOURCE})"
		}
		trap __portage_ebuild_exit EXIT
	fi

	# A reasonable default for ${S}
	[[ -z ${S} ]] && export S=${WORKDIR}/${P}

	if [[ -s ${SANDBOX_LOG} ]] ; then
		# We use SANDBOX_LOG to check for sandbox violations,
		# so we ensure that there can't be a stale log to
		# interfere with our logic.
		local x=
		if [[ -n ${SANDBOX_ON} ]] ; then
			x=${SANDBOX_ON}
			export SANDBOX_ON=0
		fi

		rm -f "${SANDBOX_LOG}" || \
			die "failed to remove stale sandbox log: '${SANDBOX_LOG}'"

		if [[ -n ${x} ]] ; then
			export SANDBOX_ON=${x}
		fi
		unset x
	fi

	# Force configure scripts that automatically detect ccache to
	# respect FEATURES="-ccache".
	if ! contains_word ccache "${FEATURES}"; then
		export CCACHE_DISABLE=1
	fi

	local ___phase_func=$(__ebuild_arg_to_phase "${EBUILD_PHASE}")
	[[ -n ${___phase_func} ]] && __ebuild_phase_funcs "${EAPI}" "${___phase_func}"

	__source_all_bashrcs

	case ${1} in
	nofetch)
		__ebuild_phase_with_hooks pkg_nofetch
		;;
	prerm|postrm|preinst|postinst|config|info)
		if [[ $1 == @(config|info) ]] && ! declare -F "pkg_${1}" >/dev/null; then
			ewarn  "pkg_${1}() is not defined: '${EBUILD##*/}'"
		fi
		export SANDBOX_ON="0"
		if [[ ${PORTAGE_DEBUG} != 1 || $- == *x* ]]; then
			__ebuild_phase_with_hooks pkg_${1}
		else
			set -x
			__ebuild_phase_with_hooks pkg_${1}
			set +x
		fi
		if [[ -n ${PORTAGE_UPDATE_ENV} ]] ; then
			# Update environment.bz2 in case installation phases
			# need to pass some variables to uninstallation phases.
			# Use safe cwd, avoiding unsafe import for bug #469338.
			cd "${PORTAGE_PYM_PATH}"
			__save_ebuild_env --exclude-init-phases | \
				__filter_readonly_variables --filter-path \
				--filter-sandbox --allow-extra-vars \
				| ${PORTAGE_BZIP2_COMMAND} -c -f9 > "${PORTAGE_UPDATE_ENV}"
			assert "__save_ebuild_env failed"
		fi
		;;
	unpack|prepare|configure|compile|test|clean|install)
		if [[ ${SANDBOX_DISABLED:-0} = 0 ]] ; then
			export SANDBOX_ON="1"
		else
			export SANDBOX_ON="0"
		fi

		case "${1}" in
		configure|compile)

			local x
			for x in ASFLAGS CCACHE_DIR CCACHE_SIZE \
				CFLAGS CXXFLAGS LDFLAGS LIBCFLAGS LIBCXXFLAGS ; do
				[[ ${!x+set} = set ]] && export ${x}
			done
			unset x

			contains_word distcc "${FEATURES}" \
			&& [[ ${DISTCC_DIR} ]] \
			&& [[ ${SANDBOX_WRITE/${DISTCC_DIR}} == ${SANDBOX_WRITE} ]] \
			&& addwrite "${DISTCC_DIR}"

			if contains_word noauto "${FEATURES}" \
				&& [[ ! -f ${PORTAGE_BUILDDIR}/.unpacked ]]
			then
				echo
				echo "!!! We apparently haven't unpacked..." \
					"This is probably not what you"
				echo "!!! want to be doing... You are using" \
					"FEATURES=noauto so I'll assume"
				echo "!!! that you know what you are doing..." \
					"You have 5 seconds to abort..."
				echo

				sleep 5
			fi

			cd "${PORTAGE_BUILDDIR}"
			if [[ ! -d build-info ]]; then
				mkdir build-info
				cp "${EBUILD}" "build-info/${PF}.ebuild"
			fi

			# Our custom version of libtool uses ${S} and ${D} to fix
			# invalid paths in .la files
			export S D

			;;
		esac

		if [[ ${PORTAGE_DEBUG} != 1 || $- == *x* ]]; then
			__dyn_${1}
		else
			set -x
			__dyn_${1}
			set +x
		fi
		export SANDBOX_ON="0"
		;;
	help|pretend|setup)
		# pkg_setup needs to be out of the sandbox for tmp file creation;
		# for example, awking and piping a file in /tmp requires a temp file to be created
		# in /etc.  If pkg_setup is in the sandbox, both our lilo and apache ebuilds break.
		export SANDBOX_ON="0"
		if [[ ${PORTAGE_DEBUG} != 1 || $- == *x* ]]; then
			__dyn_${1}
		else
			set -x
			__dyn_${1}
			set +x
		fi
		;;
	_internal_test)
		;;
	*)
		export SANDBOX_ON="1"
		echo "Unrecognized arg '${1}'"
		echo
		__dyn_help
		exit 1
		;;
	esac

	# Save the env only for relevant phases.
	if [[ $1 != @(clean|help|info|nofetch) ]]; then
		umask 002

		# Use safe cwd, avoiding unsafe import for bug #469338.
		cd "${PORTAGE_PYM_PATH}"
		__save_ebuild_env | __filter_readonly_variables \
			--filter-features > "${T}/environment"
		assert "__save_ebuild_env failed"

		chgrp "${PORTAGE_GRPNAME:-portage}" "${T}/environment"
		chmod g+w "${T}/environment"
	fi

	[[ -n ${PORTAGE_EBUILD_EXIT_FILE} ]] && : > "${PORTAGE_EBUILD_EXIT_FILE}"
	if [[ -n ${PORTAGE_IPC_DAEMON} ]] ; then
		[[ ! -s ${SANDBOX_LOG} ]]

		"${PORTAGE_BIN_PATH}"/ebuild-ipc exit $?
	fi
}
