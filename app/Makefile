TARGET = iphone:clang:9.3:9.0
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = XuperPad

XuperPad_FILES = main.m \
	Classes/XPConstants.m \
	Classes/XPCrypto.m \
	Classes/XPTransport.m \
	Classes/XPSeedPool.m \
	Classes/XPSession.m \
	Classes/XPPortalParser.m \
	Classes/XPPortalClient.m \
	Classes/XPStreamResolver.m \
	Classes/XPTitleCell.m \
	Classes/XPCatalogViewController.m \
	Classes/XPDetailViewController.m \
	Classes/XPPlayerViewController.m \
	Classes/XPAppDelegate.m

XuperPad_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation AVKit

XuperPad_LIBRARIES = c++abi

XuperPad_CFLAGS = -fobjc-arc -fblocks \
	-Wno-deprecated-declarations \
	-Wno-unused-parameter \
	-Wno-unused-variable \
	-Wno-unused-function

XuperPad_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 XuperPad 2>/dev/null || true"
