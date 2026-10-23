APP_NAME := Mixologist
BUNDLE_ID := dev.mixologist.Mixologist
VERSION := 0.1.0

BUILD_DIR := build
APP := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR := $(APP)/Contents/MacOS
RESOURCES_DIR := $(APP)/Contents/Resources
BINARY := $(MACOS_DIR)/$(APP_NAME)

SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path)
ARCH ?= $(shell uname -m)
# Matches LSMinimumSystemVersion: nothing below macOS 26 has MenuBarAgent.
DEPLOYMENT_TARGET := 26.0
TARGET := $(ARCH)-apple-macos$(DEPLOYMENT_TARGET)
# TCC keys an ad-hoc build's Accessibility grant to its cdhash, so every rebuild
# silently loses it. A real identity gives a designated requirement that stays
# stable across rebuilds; fall back to ad-hoc only when none is installed.
ifeq ($(origin CODESIGN_IDENTITY),undefined)
CODESIGN_IDENTITY := $(or $(shell security find-identity -p codesigning -v 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"'),-)
endif

OBJ_DIR := $(BUILD_DIR)/obj
OBJC_SOURCES := $(wildcard Sources/*.m)
SWIFT_SOURCES := $(wildcard Sources/*.swift)
HEADERS := $(wildcard Sources/*.h)
BRIDGING_HEADER := Sources/Mixologist-Bridging-Header.h
OBJC_OBJECTS := $(patsubst Sources/%.m,$(OBJ_DIR)/%.o,$(OBJC_SOURCES))
SWIFT_OBJECT := $(OBJ_DIR)/Swift.o
# Generated alongside SWIFT_OBJECT; lets Objective-C see the SwiftUI settings window.
SWIFT_HEADER := $(OBJ_DIR)/Mixologist-Swift.h
FRAMEWORKS := -framework Cocoa -framework ApplicationServices -framework Carbon -framework ServiceManagement

CFLAGS := -fobjc-arc -fmodules -fblocks -Wall -Wextra -Wno-unused-parameter \
          -target $(TARGET) -isysroot $(SDKROOT) -I Sources -I $(OBJ_DIR)
SWIFTFLAGS := -target $(TARGET) -sdk $(SDKROOT) -module-name $(APP_NAME) -swift-version 5 \
              -O -wmo -parse-as-library -import-objc-header $(BRIDGING_HEADER) -I Sources

.PHONY: all build sign run diagnose scan test clean install

all: $(APP)

$(SWIFT_OBJECT): $(SWIFT_SOURCES) $(HEADERS)
	@mkdir -p $(OBJ_DIR)
	swiftc $(SWIFTFLAGS) -emit-object -o $@ -emit-objc-header-path $(SWIFT_HEADER) \
	      -emit-module-path $(OBJ_DIR)/$(APP_NAME).swiftmodule $(SWIFT_SOURCES)

$(SWIFT_HEADER): $(SWIFT_OBJECT)

$(OBJ_DIR)/%.o: Sources/%.m $(HEADERS) $(SWIFT_HEADER)
	@mkdir -p $(OBJ_DIR)
	clang $(CFLAGS) -c $< -o $@

# Linking through swiftc pulls in the Swift runtime and SwiftUI.
$(BINARY): $(OBJC_OBJECTS) $(SWIFT_OBJECT)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	swiftc -target $(TARGET) -sdk $(SDKROOT) $(FRAMEWORKS) $^ -o $@

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
	@pkill -x $(APP_NAME) 2>/dev/null; while pgrep -x $(APP_NAME) >/dev/null; do sleep 0.1; done
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
