SDKROOT ?= $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then printf '%s' /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; else xcrun --sdk macosx --show-sdk-path; fi)
export SDKROOT
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/swiftpm-module-cache

.PHONY: build release test run app archive clean

build:
	swift build

release:
	swift build -c release

test:
	swift run BlobfishNative --self-test

run:
	swift run BlobfishNative

app: release
	sh scripts/package-app.sh

archive: app
	sh scripts/archive-app.sh

clean:
	swift package clean
