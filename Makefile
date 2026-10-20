# RAE: rootless only (Dopamine / palera1n rootless), arm64, iOS 15 and later.
export THEOS_PACKAGE_SCHEME = rootless
export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RAE

RAE_FILES = $(wildcard Sources/*.m) $(wildcard Sources/*.c)
RAE_FRAMEWORKS = UIKit Foundation
RAE_LDFLAGS = -lz
RAE_OBJCFLAGS = -fobjc-arc -Wno-deprecated-declarations
RAE_CFLAGS = -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/application.mk
