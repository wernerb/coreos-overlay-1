# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI="6"
PYTHON_COMPAT=( python2_7 )
PYTHON_REQ_USE="xml"

inherit multilib python-r1 toolchain-funcs bash-completion-r1

MY_P="${P//_/-}"

MY_RELEASEDATE="20190609"
EXTRAS_VER="1.36"
SEMNG_VER="${PV}"
SELNX_VER="${PV}"
SEPOL_VER="${PV}"

IUSE="audit extra nls pam dbus python semodule"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

DESCRIPTION="SELinux core utilities"
HOMEPAGE="https://github.com/SELinuxProject/selinux/wiki"

if [[ ${PV} == 9999 ]] ; then
	inherit git-r3
	EGIT_REPO_URI="https://github.com/SELinuxProject/selinux.git"
	SRC_URI="https://dev.gentoo.org/~perfinion/distfiles/policycoreutils-extra-${EXTRAS_VER}.tar.bz2"
	S1="${WORKDIR}/${MY_P}/${PN}"
	S2="${WORKDIR}/policycoreutils-extra"
	S="${S1}"
else
	SRC_URI="https://raw.githubusercontent.com/wiki/SELinuxProject/selinux/files/releases/${MY_RELEASEDATE}/${MY_P}.tar.gz
		extra? ( https://dev.gentoo.org/~perfinion/distfiles/policycoreutils-extra-${EXTRAS_VER}.tar.bz2 )"
	KEYWORDS="amd64 arm64 ~mips x86"
	S1="${WORKDIR}/${MY_P}"
	S2="${WORKDIR}/policycoreutils-extra"
	S="${S1}"
fi

LICENSE="GPL-2"
SLOT="0"

DEPEND="sys-libs/libselinux:=[python?,${PYTHON_USEDEP}]
	>=sys-libs/glibc-2.4
	>=sys-libs/libcap-1.10-r10:=
	sys-libs/libsemanage:=[python?,${PYTHON_USEDEP}]
	sys-libs/libcap-ng:=
	sys-libs/libsepol
	>=app-admin/setools-4.1.1[python?,${PYTHON_USEDEP}]
	nls? ( sys-devel/gettext )
	python? (
		dev-python/ipy[${PYTHON_USEDEP}]
	)
	dbus? (
		sys-apps/dbus
		dev-libs/dbus-glib:=
	)
	audit? ( >=sys-process/audit-1.5.1[python?,${PYTHON_USEDEP}] )
	pam? ( sys-libs/pam:= )
	python? (
		${PYTHON_DEPS}
	)
	!<sec-policy/selinux-base-policy-2.20151208-r6"
# 2.20151208-r6 and higher has support for new setfiles

### libcgroup -> seunshare
### dbus -> restorecond

# pax-utils for scanelf used by rlpkg
RDEPEND="${DEPEND}
	app-misc/pax-utils
	!<sys-apps/openrc-0.14"

PDEPEND="
	semodule? ( sys-apps/semodule-utils )
	python? (
		sys-apps/selinux-python
	)"

src_unpack() {
	# Override default one because we need the SRC_URI ones even in case of 9999 ebuilds
	default
	if [[ ${PV} == 9999 ]] ; then
		git-r3_src_unpack
	fi
}

src_prepare() {
	S="${S1}"
	cd "${S}" || die "Failed to switch to ${S}"
	if [[ ${PV} != 9999 ]] ; then
		# If needed for live ebuilds please use /etc/portage/patches
		eapply "${FILESDIR}/policycoreutils-2.7-0001-newrole-not-suid.patch"
	fi

	# rlpkg is more useful than fixfiles
	sed -i -e '/^all/s/fixfiles//' "${S}/scripts/Makefile" \
		|| die "fixfiles sed 1 failed"
	sed -i -e '/fixfiles/d' "${S}/scripts/Makefile" \
		|| die "fixfiles sed 2 failed"

	eapply_user

	sed -i 's/-Werror//g' "${S1}"/*/Makefile || die "Failed to remove Werror"

	if use python ; then
		python_copy_sources
		# Our extra code is outside the regular directory, so set it to the extra
		# directory. We really should optimize this as it is ugly, but the extra
		# code is needed for Gentoo at the same time that policycoreutils is present
		# (so we cannot use an additional package for now).
		if use extra ; then
			S="${S2}"
			python_copy_sources
		fi
	fi

	# Skip building unneeded parts.
	if ! use python ; then
		for dir in audit2allow gui scripts semanage sepolicy sepolgen-ifgen; do
			sed -e "s/ $dir / /" -i Makefile || die
		done
	fi

	use nls || sed -e "s/ po / /" -i Makefile || die
}

src_compile() {
	building() {
		emake -C "${BUILD_DIR}" \
			AUDIT_LOG_PRIVS="y" \
			AUDITH="$(usex audit y n)" \
			PAMH="$(usex pam y n)" \
			INOTIFYH="$(usex dbus y n)" \
			SESANDBOX="n" \
			CC="$(tc-getCC)" \
			PYLIBVER="${EPYTHON}" \
			LIBDIR="\$(PREFIX)/$(get_libdir)"
	}
	if use python ; then
		S="${S1}" # Regular policycoreutils
		python_foreach_impl building
		if use extra ; then
			S="${S2}" # Extra set
			python_foreach_impl building
		fi
	else
		BUILD_DIR="${S1}"
		building
		if use extra ; then
			BUILD_DIR="${S2}"
			building
		fi
	fi
}

src_install() {
	# Python scripts are present in many places. There are no extension modules.
	installation-policycoreutils() {
		einfo "Installing policycoreutils"
		emake -C "${BUILD_DIR}" DESTDIR="${D}" \
			AUDITH="$(usex audit y n)" \
			PAMH="$(usex pam y n)" \
			INOTIFYH="$(usex dbus y n)" \
			SESANDBOX="n" \
			AUDIT_LOG_PRIV="y" \
			LIBDIR="\$(PREFIX)/$(get_libdir)" \
			install
		if use python ; then
			python_optimize
		fi
	}

	installation-extras() {
		einfo "Installing policycoreutils-extra"
		emake -C "${BUILD_DIR}" \
			DESTDIR="${D}" \
			INOTIFYH="$(usex dbus)" \
			SHLIBDIR="${D}$(get_libdir)/rc" \
			install
		if use python ; then
			python_optimize
		fi
	}

	if use python ; then
		S="${S1}" # policycoreutils
		python_foreach_impl installation-policycoreutils
		if use extra ; then
			S="${S2}"
			installation-extras
			S="${S1}" # back for later
		fi
	else
		BUILD_DIR="${S1}"
		installation-policycoreutils
		if use extra ; then
			BUILD_DIR="${S2}"
			installation-extras
		fi
	fi

	# remove redhat-style init script
	rm -fR "${D}/etc/rc.d" || die

	# compatibility symlinks
	bashcomp_alias setsebool getsebool

	# location for policy definitions
	dodir /usr/lib/selinux/policy
	dosym ../../usr/lib/selinux/policy /var/lib/selinux
	keepdir /usr/lib/selinux/policy

	if use python ; then
		# Set version-specific scripts
		for pyscript in audit2allow sepolgen-ifgen sepolicy chcat; do
		  python_replicate_script "${ED}/usr/bin/${pyscript}"
		done
		python_replicate_script "${ED}/usr/sbin/semanage"
		use extra && python_replicate_script "${ED}/usr/sbin/rlpkg"
	fi
}

pkg_postinst() {
	for POLICY_TYPE in ${POLICY_TYPES} ; do
		# There have been some changes to the policy store, rebuilding now.
		# https://marc.info/?l=selinux&m=143757277819717&w=2
		einfo "Rebuilding store ${POLICY_TYPE} (without re-loading)."
		semodule -s "${POLICY_TYPE}" -n -B || die "Failed to rebuild policy store ${POLICY_TYPE}"
	done
}