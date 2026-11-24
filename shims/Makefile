# GRID Legends shims. VXpro's shims (third_party/VXpro/shims) are built first into the same directory; the gl*
# libraries re-export them (or the visionOS framework) and add what GRID Legends imports beyond them.
#   make            -> ../build/xros   (Vision Pro)
#   make sim        -> ../build/xrsim  (visionOS simulator)
VXPRO := $(abspath ../third_party/VXpro)
OUT := $(abspath ../build/xros)
SDKNAME := xros
TARGET := arm64-apple-xros26.0
SDK = $(shell xcrun --sdk $(SDKNAME) --show-sdk-path)
CC = xcrun --sdk $(SDKNAME) clang
CFLAGS = -target $(TARGET) -isysroot $(SDK) -O2 -Wall -Wno-unused-parameter -fobjc-arc -fvisibility=default
DY = -dynamiclib -install_name @rpath/$(notdir $@) -Wl,-headerpad_max_install_names
KITLIB = $(OUT)/libglkit.dylib
VXKIT = $(OUT)/libvxkit.dylib
KIT = $(KITLIB) $(VXKIT)

GL := libglkit libglcarbon libglcs libglcg libglsec libglcv libglal libglff libglcf libglfoundation libglavf libglcollab libglmtl libglappsvc libglsbridge libglsystem libgliokit libglwebkit libglca
all: vxpro $(addprefix $(OUT)/,$(addsuffix .dylib,$(GL)))

vxpro:
	$(MAKE) -C $(VXPRO)/shims OUT=$(OUT) $(VXPRO_ARGS) all

SIMSDK = $(shell xcrun --sdk xrsimulator --show-sdk-path)
sim:
	$(MAKE) OUT=$(abspath ../build/xrsim) SDKNAME=xrsimulator TARGET=arm64-apple-xros26.0-simulator \
	  VXPRO_ARGS='FXLINK= SDK=$(SIMSDK) CC="xcrun --sdk xrsimulator clang" CFLAGS="-target arm64-apple-xros26.0-simulator -isysroot $(SIMSDK) -O2 -Wall -Wno-unused-parameter -fobjc-arc -fvisibility=default"' all

$(KITLIB): glkit.m glcommon.m glcommon.h vxpro
	$(CC) $(CFLAGS) $(DY) glkit.m glcommon.m -o $@ -Wl,-reexport_library,$(VXKIT) -framework Foundation
$(OUT)/libglcarbon.dylib: glcarbon.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glcarbon.c -o $@ -Wl,-reexport_library,$(OUT)/libvxcarbon.dylib -framework CoreFoundation $(KIT)
$(OUT)/libglcs.dylib: glcs.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glcs.c -o $@ -Wl,-reexport_framework,CoreServices -Wl,-reexport-lSystem -framework CoreFoundation $(KIT)
$(OUT)/libglcg.dylib: glcg.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glcg.c -o $@ -Wl,-reexport_library,$(OUT)/libvxcg.dylib -framework CoreFoundation -framework CoreGraphics -framework Metal $(KIT)
$(OUT)/libglsec.dylib: glsec.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glsec.c -o $@ -Wl,-reexport_library,$(OUT)/libvxsec.dylib $(KIT)
$(OUT)/libglcv.dylib: glcv.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glcv.c -o $@ -Wl,-reexport_framework,CoreVideo -framework CoreFoundation $(KIT)
$(OUT)/libglal.dylib: glal.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glal.c -o $@ $(KIT)
$(OUT)/libglff.dylib: glff.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glff.c -o $@ $(KIT)
$(OUT)/libglcf.dylib: glcf.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glcf.c -o $@ -Wl,-reexport_framework,CoreFoundation $(KIT)
$(OUT)/libglfoundation.dylib: glfoundation.m glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glfoundation.m -o $@ -Wl,-reexport_framework,Foundation $(KIT)
$(OUT)/libglavf.dylib: glsmall.m glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) -DGL_AVF glsmall.m -o $@ -Wl,-reexport_framework,AVFoundation -framework Foundation $(KIT)
$(OUT)/libglcollab.dylib: glsmall.m glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) -DGL_COLLAB glsmall.m -o $@ -framework Foundation $(KIT)
$(OUT)/libglmtl.dylib: glmtl.m glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glmtl.m -o $@ -Wl,-reexport_library,$(OUT)/libvxmtl.dylib -framework Foundation -framework Metal $(KIT)
$(OUT)/libglappsvc.dylib $(OUT)/libglsbridge.dylib: glsmall.m | vxpro
	$(CC) $(CFLAGS) $(DY) glsmall.m -o $@ -framework Foundation

$(OUT)/libglsystem.dylib: glsystem.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glsystem.c -o $@ -Wl,-reexport_library,$(OUT)/libvxsystem.dylib $(KIT)

$(OUT)/libgliokit.dylib: gliokit.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) gliokit.c -o $@ -Wl,-reexport_library,$(OUT)/libvxiokit.dylib -framework IOKit -framework CoreFoundation $(KIT)

$(OUT)/libglwebkit.dylib: glwebkit.m glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glwebkit.m -o $@ -Wl,-reexport_framework,WebKit -framework Foundation $(KIT)

$(OUT)/libglca.dylib: glca.c glcommon.h $(KITLIB)
	$(CC) $(CFLAGS) $(DY) glca.c -o $@ -Wl,-reexport_framework,CoreAudio -framework CoreFoundation $(KIT)

clean:
	rm -rf $(abspath ../build/xros) $(abspath ../build/xrsim)
.PHONY: all sim vxpro clean
