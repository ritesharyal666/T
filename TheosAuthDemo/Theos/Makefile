# Makefile — builds TheosAuthDemo as a standalone iOS application.
#
#   make package           # build a .deb
#   make do                # build + install to THEOS_DEVICE_IP
#
# A login/register/home app needs its own UI, so this is an `application`
# target (application.mk), NOT a Logos tweak. There is therefore no Tweak.x;
# main.m + AppDelegate.m are the entry points.

TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

# ARC is enabled per-file via *_CFLAGS below.
include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = TheosAuthDemo

TheosAuthDemo_FILES = \
	main.m \
	AppDelegate.m \
	Theme.m \
	CryptoManager.m \
	NetworkManager.m \
	AuthManager.m \
	LoginViewController.m \
	RegisterViewController.m \
	HomeViewController.m

TheosAuthDemo_FRAMEWORKS = UIKit CoreGraphics Foundation Security
TheosAuthDemo_CFLAGS = -fobjc-arc

include $(THEOS)/makefiles/application.mk
