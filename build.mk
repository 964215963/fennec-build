#
#    Fennec build scripts
#    Copyright (C) 2020-2022  Matías Zúñiga, Andrew Nayenko
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as
#    published by the Free Software Foundation, either version 3 of the
#    License, or (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

.ONESHELL:
SHELL = /bin/bash

# We publish the artifacts into a local Maven repository instead of using the
# auto-publication workflow because the latter does not work for Gradle
# plugins (Glean).

android-sdk:
	set -e
	# Set up Android SDK
	sdkmanager 'build-tools;31.0.0'
	sdkmanager 'build-tools;33.0.0'
	sdkmanager 'build-tools;33.0.1'
	sdkmanager 'ndk;25.0.8775105' # for GleanAS
	sdkmanager 'ndk;25.1.8937393' # for Glean
	sdkmanager 'ndk;25.2.9519653'

rust:
	set -e
	# Set up Rust
	../srclib/rustup/rustup-init.sh -y
	# shellcheck disable=SC1090,SC1091
	source "$HOME/.cargo/env"
	rustup default 1.73.0
	rustup target add thumbv7neon-linux-androideabi
	rustup target add armv7-linux-androideabi
	rustup target add aarch64-linux-android
	cargo install --force --vers 0.26.0 cbindgen

wasi-sdk:
	set -e
	# Build WASI SDK
	pushd ../srclib/wasi-sdk
	mkdir -p build/install/wasi
	touch build/compiler-rt.BUILT # fool the build system
	make \
	    PREFIX=/wasi \
	    build/wasi-libc.BUILT \
	    build/libcxx.BUILT \
	    -j"$(nproc)"
	popd

microg:
	set -e
	# Build microG libraries
	pushd ../srclib/gmscore
	gradle -x javaDocReleaseGeneration \
	    :play-services-ads-identifier:publishToMavenLocal \
	    :play-services-base:publishToMavenLocal \
	    :play-services-basement:publishToMavenLocal \
	    :play-services-fido:publishToMavenLocal \
	    :play-services-tasks:publishToMavenLocal
	popd

mozilla-release: android-sdk rust wasi-sdk microg
	set -e
	pushd ../srclib/MozFennec
	MOZ_CHROME_MULTILOCALE=$(< "$patches/locales")
	export MOZ_CHROME_MULTILOCALE
	./mach --verbose build
	gradle publishWithGeckoBinariesReleasePublicationToMavenLocal
	gradle exoplayer2:publishReleasePublicationToMavenLocal
	popd

glean-as:
	set -e
	pushd ../srclib/MozGleanAS
	export TARGET_CFLAGS=-DNDEBUG
	gradle publishToMavenLocal
	popd

glean:
	set -e
	pushd ../srclib/MozGlean
	gradle publishToMavenLocal
	popd

android-components-as:
	set -e
	pushd ../srclib/FirefoxAndroidAS/android-components
	gradle publishToMavenLocal
	popd

application-services: glean-as android-components-as
	set -e
	pushd ../srclib/MozAppServices
	export SQLCIPHER_LIB_DIR="$application_services/libs/desktop/linux-x86-64/sqlcipher/lib"
	export SQLCIPHER_INCLUDE_DIR="$application_services/libs/desktop/linux-x86-64/sqlcipher/include"
	export NSS_DIR="$application_services/libs/desktop/linux-x86-64/nss"
	export NSS_STATIC=1
	./libs/verify-android-environment.sh
	gradle publishToMavenLocal
	popd

android-components:
	set -e
	pushd android-components
	gradle publishToMavenLocal
	popd

fenix: application-services android-components
	set -e
	pushd fenix
	gradle assembleRelease
	popd

.PHONY: fenix android-sdk application-services android-components android-components-as glean glean-as microg mozilla-release rust wasi-sdk
