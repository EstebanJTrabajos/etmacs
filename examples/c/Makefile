CC ?= cc
CFLAGS ?= -std=c11 -Wall -Wextra -g -O0
TARGET := build/main

.PHONY: all clean

all: $(TARGET)

$(TARGET): main.c | build
	$(CC) $(CFLAGS) -o $@ $<

build:
	mkdir -p build

clean:
	rm -rf build
