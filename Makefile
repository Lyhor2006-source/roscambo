# =============================================================================
# Makefile for RosCambo iOS Cheat (arm64)
# Compatible with macOS (Xcode SDK) & Linux / VPS with cctools-port / clang
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

CXXFLAGS = $(ARCHS) $(MIN_VER) $(ISYSROOT) -O3 -std=c++17 -fno-objc-arc \
           -I. -I./imgui -I./imgui/backends \
           -Wall -fvisibility=hidden -DNDEBUG

LDFLAGS = $(ARCHS) $(MIN_VER) $(ISYSROOT) -dynamiclib \
          -framework UIKit -framework Metal -framework MetalKit \
          -framework QuartzCore -framework Foundation \
          -install_name @executable_path/roscheat.dylib

SRCS = RosCheatMetal.mm \
       imgui/imgui.cpp \
       imgui/imgui_draw.cpp \
       imgui/imgui_tables.cpp \
       imgui/imgui_widgets.cpp \
       imgui/backends/imgui_impl_metal.mm

OBJS = $(SRCS:.mm=.o)
OBJS := $(OBJS:.cpp=.o)

all: $(TARGET)

%.o: %.mm
	$(CC) $(CXXFLAGS) -c $< -o $@

%.o: %.cpp
	$(CC) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) -o $(TARGET)
	strip -x $(TARGET)
	which ldid > /dev/null 2>&1 && ldid -S $(TARGET) || true
	@echo "==> Build complete: $(TARGET) (arm64)"

clean:
	rm -f $(TARGET) $(OBJS)
