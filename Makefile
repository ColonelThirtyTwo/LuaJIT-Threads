
UNAME := $(shell uname)

CC = gcc
CFLAGS = -Wall -g -std=c99 -shared -llua51
LUAJIT = luajit

ifeq ($(UNAME), Linux)
# Linux
CFLAGS += -f PIC
OUT = libluajitthreads.so

else
# Windows
CFLAGS += -D WINDOWS
OUT = luajitthreads.dll

endif

all: $(OUT)

$(OUT): luajitthreads.c
	$(CC) $(CFLAGS) -o $(OUT) luajitthreads.c

test: all
	$(LUAJIT) tests.lua

.PHONY: all test
