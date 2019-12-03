# Copyright (c) 2017-2018 CoreOS, Inc.. All rights reserved.
# Distributed under the terms of the GNU General Public License v2

EAPI=7
CROS_WORKON_PROJECT="flatcar-linux/torcx"
CROS_WORKON_LOCALNAME="torcx"
CROS_WORKON_REPO="git://github.com"
COREOS_GO_PACKAGE="github.com/coreos/torcx"

if [[ "${PV}" == 9999 ]]; then
	KEYWORDS="~amd64 ~arm64"
else
	CROS_WORKON_COMMIT="0be7010228fde886b787bbf0aeede466b86f7cd4" # v0.2.0
	KEYWORDS="amd64 arm64"
fi

inherit coreos-go cros-workon systemd

DESCRIPTION="torcx is a boot-time addon manager for immutable systems"
HOMEPAGE="https://github.com/coreos/torcx"
LICENSE="Apache-2.0"
SLOT="0"

src_compile() {
	CGO_ENABLED=0 go_export
	${EGO} build -v \
		-p "$(makeopts_jobs)" \
		-ldflags "-X ${COREOS_GO_PACKAGE}/pkg/version.VERSION=${PV}" \
		-o "bin/${ARCH}/torcx" \
		-tags containers_image_openpgp \
		"${COREOS_GO_PACKAGE}"
}

src_install() {
	local generatordir=/usr/lib/systemd/system-generators
	local vendordir=/usr/share/torcx
	local libcoreosdir=/usr/lib/flatcar

	# Install generator and userland.
	exeinto "${generatordir}"
	newexe "${S}/bin/${ARCH}/torcx" torcx-generator
	dosym ../systemd/system-generators/torcx-generator "${libcoreosdir}/torcx"
	systemd_dounit "${FILESDIR}/torcx.target"

	insinto "${vendordir}/profiles"
	doins "${FILESDIR}/docker-1.12-no.json"
	doins "${FILESDIR}/docker-1.12-yes.json"
	doins "${FILESDIR}/vendor.json"
	dodir "${vendordir}/store"

	# Preserve program paths for torcx packages.
	newbin "${FILESDIR}/compat-wrapper.sh" docker
	for link in {docker-,}{containerd{,-shim},runc} ctr docker-{init,proxy} dockerd tini
	do ln -fns docker "${ED}/usr/bin/${link}"
	done
	exeinto /usr/lib/flatcar
	newexe "${FILESDIR}/dockerd-wrapper.sh" dockerd
}
