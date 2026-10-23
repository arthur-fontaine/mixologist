APP_NAME := Mixologist
BUNDLE_ID := dev.mixologist.Mixologist
VERSION := 0.1.0

BUILD_DIR := build
APP := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP)/Contents/MacOS
RESOURCES_DIR := $(APP)/Contents/Resources
BINARY := $(MACOS_DIR)/$(APP_NAME)

SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path)
ARCHS ?= $(shell uname -m)
CODESIGN_IDENTITY ?= -

SOURCES := $(wildcard Sources/*.m)
HEADERS := $(wildcard Sources/*.h)
FRAMEWORKS := -framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement

CFLAGS := -fobjc-arc -fmodules -fblocks -Wall -Wextra -Wno-unused-parameter \
          -mmacosx-version-min=14.0 -isysroot $(SDKROOT) -I Sources
LDFLAGS := -isysroot $(SDKROOT) -mmacosx-version-min=14.0 $(FRAMEWORKS)

# The pinned Nix apple-sdk predates macOS 26, so the compiler deployment target
# stays at 14.0. Info.plist's LSMinimumSystemVersion=26.0 is what prevents the
# app from launching on systems without MenuBarAgent. The code only uses public
# APIs that exist on 14 plus the private framework loaded at runtime.

ARCH_FLAGS := $(foreach arch,$(ARCHS),-arch $(arch))

.PHONY: all build sign run diagnose scan test clean install

all: $(APP)

$(BINARY): $(SOURCES) $(HEADERS)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	clang $(CFLAGS) $(ARCH_FLAGS) $(SOURCES) $(LDFLAGS) -o $@

$(APP): $(BINARY) Resources/Info.plist
	@mkdir -p $(RESOURCES_DIR)
	@cp Resources/Info.plist $(APP)/Contents/Info.plist
	@printf 'APPL????' > $(APP)/Contents/PkgInfo
	@plutil -lint $(APP)/Contents/Info.plist >/dev/null
	@$(MAKE) --no-print-directory sign

sign:
	@codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP)" >/dev/null 2>&1 || \
	  codesign --force --deep --sign - "$(APP)"
	@echo "Signed $(APP) with $(CODESIGN_IDENTITY)"

run: $(APP)
	open "$(APP)"

diagnose: $(APP)
	"$(BINARY)" --diagnose

scan: $(APP)
	"$(BINARY)" --scan

test: $(APP)
	"$(BINARY)" --self-test

clean:
	rm -rf $(BUILD_DIR)

install: $(APP)
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" "/Applications/$(APP_NAME).app"
	@echo "Installed /Applications/$(APP_NAME).app"
