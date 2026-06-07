# Makefile for writer application

CROSS_COMPILE ?=

CC := $(CROSS_COMPILE)gcc

TARGET := writer
SRCS := writer.c
OBJS := $(SRCS:.c=.o)

CFLAGS := -Wall -Wextra -Werror -g

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(CFLAGS) -o $(TARGET) $(OBJS)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)
