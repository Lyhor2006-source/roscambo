# =============================================================================
# Makefile for RosCambo iOS Cheat Wrapper (arm64)
# =============================================================================

TARGET = roscheat.dylib

# Detect toolchain
ifeq ($(shell uname -s), Darwin)
    CC = xcrun -sdk iphoneos clang++
    MIN_VER = -miphoneos-version-min=14.0
    SYSROOT = $(shell xcrun -sdk iphoneos --show-sdk-path)
    ISYSROOT = -isysroot $(SYSROOT)
else
    CC = clang++
    MIN_VER = -miphoneos-version-min=14.0
    ISYSROOT = 
endif

ARCHS = -arch arm64

CXXFLAGS = $(ARCHS) $(MIN_VER) $(ISYSROOT) -O3 -std=c++17 -fno-objc-arc -fobjc-exceptions \
           -I. -Wall -fvisibility=hidden -DNDEBUG

LDFLAGS = $(ARCHS) $(MIN_VER) $(ISYSROOT) -dynamiclib \
          -framework UIKit -framework Metal -framework MetalKit \
          -framework QuartzCore -framework Foundation \
          -install_name @executable_path/roscheat.dylib

SRCS = RyomenWrapper.mm

OBJS = $(SRCS:.mm=.o)

all: $(TARGET)

%.o: %.mm
	$(CC) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $(TARGET)
	strip -x $(TARGET)
	which ldid > /dev/null 2>&1 && ldid -S $(TARGET) || true
	@echo "==> Build complete: $(TARGET) (arm64)"

clean:
	rm -f $(TARGET) $(OBJS)
