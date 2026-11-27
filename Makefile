ARCHS = arm64 arm64e
TARGET = iphone:clang:17.0:15.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoOnlineWallpaper
AutoOnlineWallpaper_FILES = Tweak.xm
AutoOnlineWallpaper_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AutoOnlineWallpaper_FRAMEWORKS = UIKit Foundation
AutoOnlineWallpaper_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"

SUBPROJECTS += Preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
