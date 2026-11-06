export ARCHS = arm64 arm64e
export TARGET = iphone:clang:latest:14.0
export PACKAGE_VERSION = 1.6.3-beta2

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Glint
Glint_FILES = Tweak.xm $(wildcard Sources/*.m)
Glint_CFLAGS = -fobjc-arc -IHeaders -ISources -Wno-deprecated-declarations -DGLINT_VERIFICATION_BUILD=1
Glint_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore CoreLocation \
                   Contacts MessageUI
Glint_LIBRARIES = substrate
Glint_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 SpringBoard"
