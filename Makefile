ARCHS = arm64 arm64e
TARGET = iphone:clang:17.0:15.0
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AutoOnlineWallpaper

AutoOnlineWallpaper_FILES = Tweak.xm
AutoOnlineWallpaper_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AutoOnlineWallpaper_FRAMEWORKS = UIKit SystemConfiguration CoreTelephony

include $(THEOS_MAKE_PATH)/tweak.mk

# 关键：加上下面这两行，告诉 Theos 还有设置面板需要一起编译
SUBPROJECTS += autoonlinewallpaperprefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
