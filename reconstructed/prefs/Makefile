include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = GlintPrefs

GlintPrefs_FILES = GLTRootListController.m GLTCells.m
GlintPrefs_FRAMEWORKS = UIKit Foundation
GlintPrefs_PRIVATE_FRAMEWORKS = Preferences
GlintPrefs_INSTALL_PATH = /Library/PreferenceBundles
GlintPrefs_CFLAGS = -fobjc-arc -IResources -Wno-deprecated-declarations
GlintPrefs_RESOURCE_DIRS = Resources
GlintPrefs_RESOURCE_FILES = Resources/Root.plist Resources/Info.plist \
                            Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png

include $(THEOS_MAKE_PATH)/bundle.mk
