SDKROOT ?= $(shell if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]; then printf '%s' /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk; else xcrun --sdk macosx --show-sdk-path; fi)
export SDKROOT
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/swiftpm-module-cache

.PHONY: build test run clean

build:
	swift build

test:
	swift run BlobfishNative --self-test

run:
	swift run BlobfishNative

clean:
	swift package clean
