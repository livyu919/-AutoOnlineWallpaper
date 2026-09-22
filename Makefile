ARCHS = arm64 arm64e
TARGET = iphone:clang:17.0:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoOnlineWallpaper

AutoOnlineWallpaper_FILES = Tweak.xm
AutoOnlineWallpaper_CFLAGS = -fobjc-arc
AutoOnlineWallpaper_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
