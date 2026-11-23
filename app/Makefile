XUPER_FFMPEG_SDK_VERSION ?= 9.3
XUPER_PIC_FLAGS ?= -fPIC
ifneq ($(wildcard vendor/ffmpeg/ldconfig.mk),)
include vendor/ffmpeg/ldconfig.mk
endif
ifneq ($(wildcard vendor/ffmpeg/picflags.mk),)
include vendor/ffmpeg/picflags.mk
endif

TARGET = iphone:clang:$(XUPER_FFMPEG_SDK_VERSION):9.0
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
	Classes/XPTheme.m \
	Classes/XPStore.m \
	Classes/XPImageCache.m \
	Classes/XPDrawnLabel.m \
	Classes/XPDrawnImageView.m \
	Classes/XPDrawnScrollView.m \
	Classes/XPDrawnTextField.m \
	Classes/XPDrawnCollectionViewCell.m \
	Classes/XPDrawnCollectionView.m \
	Classes/XPDrawnNavigationController.m \
	Classes/XPButton.m \
	Classes/XPChipButton.m \
	Classes/XPSearchField.m \
	Classes/XPCardCell.m \
	Classes/XPSectionHeaderView.m \
	Classes/XPStatusView.m \
	Classes/XPTabBar.m \
	Classes/XPBackControl.m \
	Classes/XPRootViewController.m \
	Classes/XPCatalogViewController.m \
	Classes/XPLibraryViewController.m \
	Classes/XPSettingsViewController.m \
	Classes/XPDetailViewController.m \
	Classes/XPPlayerViewController.m \
	Classes/XPPlayerControls.m \
	Classes/XPChapterBar.m \
	Classes/XPDecoder.m \
	Classes/XPGLView.m \
	Classes/XPAudioOutput.m \
	Classes/XPOptionsPanel.m \
	Classes/XPSubtitleOverlay.m \
	Classes/XPAppDelegate.m

XuperPad_FRAMEWORKS = UIKit Foundation CoreGraphics AVFoundation AVKit AudioToolbox OpenGLES QuartzCore

XuperPad_LIBRARIES = c++abi

XUPER_SDK_SYSROOT := $(THEOS_SDKS_PATH)/iPhoneOS$(XUPER_FFMPEG_SDK_VERSION).sdk
ifneq ($(wildcard $(XUPER_SDK_SYSROOT)/usr/lib/libxuperlibc.tbd),)
XuperPad_LIBRARIES += xuperlibc
endif

XuperPad_CFLAGS = -fobjc-arc -fblocks \
	-fno-optimize-sibling-calls \
	$(XUPER_PIC_FLAGS) \
	-I$(CURDIR)/vendor/ffmpeg/include \
	-Wno-deprecated-declarations \
	-Wno-unused-parameter \
	-Wno-unused-variable \
	-Wno-unused-function

XuperPad_LDFLAGS = $(CURDIR)/vendor/ffmpeg/lib/libavformat.a \
	$(CURDIR)/vendor/ffmpeg/lib/libavcodec.a \
	$(CURDIR)/vendor/ffmpeg/lib/libswscale.a \
	$(CURDIR)/vendor/ffmpeg/lib/libswresample.a \
	$(CURDIR)/vendor/ffmpeg/lib/libavutil.a \
	$(CURDIR)/vendor/ffmpeg/lib/libmbedtls.a \
	$(CURDIR)/vendor/ffmpeg/lib/libmbedx509.a \
	$(CURDIR)/vendor/ffmpeg/lib/libmbedcrypto.a \
	-lm

XuperPad_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

after-install::
	install.exec "killall -9 XuperPad 2>/dev/null || true"
