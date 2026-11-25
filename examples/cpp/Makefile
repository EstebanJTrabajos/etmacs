CXX ?= c++
CXXFLAGS ?= -std=c++20 -Wall -Wextra -g -O0
TARGET := build/main

.PHONY: all clean

all: $(TARGET)

$(TARGET): main.cpp | build
	$(CXX) $(CXXFLAGS) -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build
