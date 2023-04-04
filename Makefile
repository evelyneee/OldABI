.PHONY: all deb-ios-rootless deb-ios-rootful

ifneq ($(ONLY_TAG),)
VERSION := $(shell git describe --tags --abbrev=0 | sed 's/^v//g')
else
VERSION := $(shell git describe --tags --always | sed 's/-/~/' | sed 's/-/\./g' | sed 's/\.g/\./g' | sed 's/^v//g')
endif

COMMON_OPTIONS = BUILD_DIR="build/" CODE_SIGNING_ALLOWED="NO" CODE_SIGNING_REQUIRED="NO" CODE_SIGN_IDENTITY="" -configuration $(CONFIGURATION)

ifneq ($(RELEASE),)
CONFIGURATION = Release
DEB_VERSION = $(VERSION)
else
CONFIGURATION = Debug
DEB_VERSION = $(VERSION)+debug
endif

ifneq ($(MAC),)
$(error macOS is not supported yet)
COMMON_OPTIONS += -destination 'generic/platform=macOS'
else
COMMON_OPTIONS += -destination 'generic/platform=iOS'
endif

ifneq ($(MAC),)
PRODUCTS_DIR = build/$(CONFIGURATION)-macosx
else
PRODUCTS_DIR = build/$(CONFIGURATION)-iphoneos
endif

STAGE_DIR = work-$(ARCHITECTURE)/stage
INSTALL_ROOT = $(STAGE_DIR)/$(INSTALL_PREFIX)

# TODO: maybe split each scheme into its own target?

all: deb

clean:
	xcodebuild -scheme OldABI $(COMMON_OPTIONS) clean

build-ios:
	xcodebuild -scheme OldABI $(COMMON_OPTIONS)

build-macos:
	# TODO
	$(error macOS is not supported yet)

deb-ios-rootful: ARCHITECTURE = iphoneos-arm
deb-ios-rootful: INSTALL_PREFIX = 

deb-ios-rootless: ARCHITECTURE = iphoneos-arm64
deb-ios-rootless: INSTALL_PREFIX = /var/jb

deb-ios-rootful deb-ios-rootless: build-ios
	@rm -rf work-$(ARCHITECTURE)
	@mkdir -p $(STAGE_DIR)

	@# Because BSD install does not support -D
	@mkdir -p $(INSTALL_ROOT)/usr/lib/ellekit

	@install -m644 $(PRODUCTS_DIR)/OldABI.dylib $(INSTALL_ROOT)/usr/lib/ellekit/OldABI.dylib
	
	@ldid -S $(INSTALL_ROOT)/usr/lib/ellekit/OldABI.dylib

	@mkdir -p $(STAGE_DIR)/DEBIAN
	@sed -e "s|@DEB_VERSION@|$(DEB_VERSION)|g" -e "s|@DEB_ARCH@|$(ARCHITECTURE)|g" packaging/control >$(STAGE_DIR)/DEBIAN/control

	@mkdir -p packages
	dpkg-deb -Zzstd --root-owner-group -b $(STAGE_DIR) packages/oldabi_$(DEB_VERSION)_$(ARCHITECTURE).deb
	
	@rm -rf work-$(ARCHITECTURE)

deb-ios: deb-ios-rootful deb-ios-rootless

deb-macos: build-macos
	# TODO
	$(error macOS is not supported yet)

ifneq ($(MAC),)
deb: deb-macos
else
deb: deb-ios
endif

ifneq ($(MAC),)
build: build-macos
else
build: build-ios
endif
