#
# Use 'make help' to list available targets.
#
# Define V=1 to enable "verbose" mode, showing all executed commands.
#
# Define DECOMPRESSION_ONLY to omit all compression code, building a
# decompression-only library.  If doing this, you must also build a specific
# library target such as 'libdeflate.a', as the programs will no longer compile.
#
# Define DISABLE_GZIP to disable support for the gzip wrapper format.
#
# Define DISABLE_ZLIB to disable support for the zlib wrapper format.
#
##############################################################################

#### Common compiler flags.
#### Flags given here are not intended to be overridden, but you can add more
#### by defining CFLAGS in the environment or on the 'make' command line.

cc-option = $(shell if $(CXX) $(1) -c -x c /dev/null -o /dev/null \
	      1>&2 2>/dev/null; then echo $(1); fi)

override CFLAGS :=							\
        $(CFLAGS) -O4 -flto -march=native -mtune=native -fomit-frame-pointer -std=c++14 -I. -Icommon -lpthread	\
	-Iexternal/type_safe/include					\
	-Iexternal/type_safe/external/debug_assert			\
	-Wall -Wundef							\
	$(call cc-option,-Wpedantic)					\
	$(call cc-option,-Wvla)



##############################################################################

STATIC_LIB_SUFFIX := .a
SHARED_LIB_SUFFIX := .so
SHARED_LIB_CFLAGS := -fPIC
PROG_SUFFIX       :=
PROG_CFLAGS       :=
HARD_LINKS        := 1

AR := gcc-ar

#debugging options for decompression (Rayan)
# some general-purpose block-level debug, useful to trace block seeks and block size
ifeq ($(deb),1)
	 LIB_CFLAGS+= -DDEB=1
endif

# very verbose output to print whole decompression process of first block
ifeq ($(first),1)
	 LIB_CFLAGS+= -DFIRST_BLOCK=1
endif

# print to stderr the whole buffer before it is parsed
ifeq ($(buf),1)
	 LIB_CFLAGS+= -DDEBUG_BUFFER=1 -DRECORD_BUFFER_COUNTS_AND_BACKREFS
endif


ifeq ($(oldparser),1)
	 LIB_CFLAGS+= -DOLD_PARSER
endif






# Compiling for Windows with MinGW?
ifneq ($(findstring -mingw,$(shell $(CXX) -dumpmachine 2>/dev/null)),)
    STATIC_LIB_SUFFIX := .lib
    SHARED_LIB_SUFFIX := .dll
    SHARED_LIB_CFLAGS :=
    PROG_SUFFIX       := .exe
    PROG_CFLAGS       := -static -municode
    HARD_LINKS        :=
    override CFLAGS   := $(CFLAGS) $(call cc-option,-Wno-pedantic-ms-format)

    # If AR was not already overridden, then derive it from $(CXX).
    # Note that CC may take different forms, e.g. "cc", "gcc",
    # "x86_64-w64-mingw32-gcc", or "x86_64-w64-mingw32-gcc-6.3.1".
    # On Windows it may also have a .exe extension.
    ifeq ($(AR),ar)
        AR := $(shell echo $(CXX) | \
                sed -E 's/g?cc(-?[0-9]+(\.[0-9]+)*)?(\.exe)?$$/ar\3/')
    endif
endif

##############################################################################

#### Quiet make is enabled by default.  Define V=1 to disable.

ifneq ($(findstring s,$(MAKEFLAGS)),s)
ifneq ($(V),1)
        QUIET_CC       = @echo '  CXX     ' $@;
        QUIET_CCLD     = @echo '  CCLD    ' $@;
        QUIET_AR       = @echo '  AR      ' $@;
        QUIET_LN       = @echo '  LN      ' $@;
        QUIET_CP       = @echo '  CP      ' $@;
        QUIET_GEN      = @echo '  GEN     ' $@;
endif
endif

##############################################################################

COMMON_HEADERS := $(wildcard common/*.h)
DEFAULT_TARGETS :=

#### Library

STATIC_LIB := libdeflate$(STATIC_LIB_SUFFIX)
SHARED_LIB := libdeflate$(SHARED_LIB_SUFFIX)

LIB_CFLAGS += $(CFLAGS) -fvisibility=hidden -D_ANSI_SOURCE

LIB_HEADERS := $(wildcard lib/*.h)

LIB_SRC := lib/aligned_malloc.c lib/x86_cpu_features.c
LIB_SRC_CXX := lib/deflate_decompress.cpp
ifndef DISABLE_GZIP
    LIB_SRC += lib/gzip_decompress.c
endif

STATIC_LIB_OBJ := $(LIB_SRC:.c=.o)
STATIC_LIB_OBJ_CXX := $(LIB_SRC_CXX:.cpp=.o)
SHARED_LIB_OBJ := $(LIB_SRC:.c=.shlib.o)

# Compile static library object files
$(STATIC_LIB_OBJ): %.o: %.c $(LIB_HEADERS) $(COMMON_HEADERS) .lib-cflags
	$(QUIET_CC) $(CXX) -o $@ -c $(LIB_CFLAGS) $<
$(STATIC_LIB_OBJ_CXX): %.o: %.cpp $(LIB_HEADERS) $(COMMON_HEADERS) .lib-cflags
	$(QUIET_CC) $(CXX) -o $@ -c $(LIB_CFLAGS) $<

# Compile shared library object files
$(SHARED_LIB_OBJ): %.shlib.o: %.c $(LIB_HEADERS) $(COMMON_HEADERS) .lib-cflags
	$(QUIET_CC) $(CXX) -o $@ -c $(LIB_CFLAGS) $(SHARED_LIB_CFLAGS) -DLIBDEFLATE_DLL $<

# Create static library
$(STATIC_LIB):$(STATIC_LIB_OBJ) $(STATIC_LIB_OBJ_CXX)
	$(QUIET_AR) $(AR) cr $@ $+

DEFAULT_TARGETS += $(STATIC_LIB)

# Create shared library
$(SHARED_LIB):$(SHARED_LIB_OBJ)
	$(QUIET_CCLD) $(CXX) -o $@ $(LDFLAGS) $(LIB_CFLAGS) -shared $+

#DEFAULT_TARGETS += $(SHARED_LIB)

# Rebuild if CC or LIB_CFLAGS changed
.lib-cflags: FORCE
	@flags='$(CXX):$(LIB_CFLAGS)'; \
	if [ "$$flags" != "`cat $@ 2>/dev/null`" ]; then \
		[ -e $@ ] && echo "Rebuilding library due to new compiler flags"; \
		echo "$$flags" > $@; \
	fi

##############################################################################

#### Programs

PROG_CFLAGS += $(CFLAGS)		 \
	       -D_POSIX_C_SOURCE=200809L \
	       -D_FILE_OFFSET_BITS=64	 \
	       -DHAVE_CONFIG_H


PROG_COMMON_HEADERS := programs/prog_util.h programs/config.h
PROG_COMMON_SRC     := programs/prog_util.c programs/tgetopt.c
NONTEST_PROGRAM_SRC := programs/gzip.c
TEST_PROGRAM_SRC    := programs/benchmark.c programs/test_checksums.c \
			programs/checksum.c

NONTEST_PROGRAMS := $(NONTEST_PROGRAM_SRC:programs/%.c=%$(PROG_SUFFIX))
DEFAULT_TARGETS  += $(NONTEST_PROGRAMS)
TEST_PROGRAMS    := $(TEST_PROGRAM_SRC:programs/%.c=%$(PROG_SUFFIX))

PROG_COMMON_OBJ     := $(PROG_COMMON_SRC:%.c=%.o)
NONTEST_PROGRAM_OBJ := $(NONTEST_PROGRAM_SRC:%.c=%.o)
TEST_PROGRAM_OBJ    := $(TEST_PROGRAM_SRC:%.c=%.o)
PROG_OBJ := $(PROG_COMMON_OBJ) $(NONTEST_PROGRAM_OBJ) $(TEST_PROGRAM_OBJ)

# Generate autodetected configuration header
programs/config.h:programs/detect.sh .prog-cflags
	$(QUIET_GEN) CC="$(CXX)" CFLAGS="$(PROG_CFLAGS)" $< > $@

# Compile program object files
$(PROG_OBJ): %.o: %.c $(PROG_COMMON_HEADERS) $(COMMON_HEADERS) .prog-cflags
	$(QUIET_CC) $(CXX) -o $@ -c $(PROG_CFLAGS) $<

# Link the programs.
#
# Note: the test programs are not compiled by default.  One reason is that the
# test programs must be linked with zlib for doing comparisons.

$(NONTEST_PROGRAMS): %$(PROG_SUFFIX): programs/%.o $(PROG_COMMON_OBJ) $(STATIC_LIB)
	$(QUIET_CCLD) $(CXX) -o $@ $(LDFLAGS) $(PROG_CFLAGS) $+

$(TEST_PROGRAMS): %$(PROG_SUFFIX): programs/%.o $(PROG_COMMON_OBJ) $(STATIC_LIB)
	$(QUIET_CCLD) $(CXX) -o $@ $(LDFLAGS) $(PROG_CFLAGS) $+ -lz

ifdef HARD_LINKS
# Hard link gunzip to gzip
gunzip$(PROG_SUFFIX):gzip$(PROG_SUFFIX)
	$(QUIET_LN) ln -f $< $@
else
# No hard links; copy gzip to gunzip
gunzip$(PROG_SUFFIX):gzip$(PROG_SUFFIX)
	$(QUIET_CP) cp -f $< $@
endif

DEFAULT_TARGETS += gunzip$(PROG_SUFFIX)

# Rebuild if CC or PROG_CFLAGS changed
.prog-cflags: FORCE
	@flags='$(CXX):$(PROG_CFLAGS)'; \
	if [ "$$flags" != "`cat $@ 2>/dev/null`" ]; then \
		[ -e $@ ] && echo "Rebuilding programs due to new compiler flags"; \
		echo "$$flags" > $@; \
	fi

##############################################################################

all:$(DEFAULT_TARGETS)

test_programs:$(TEST_PROGRAMS)

help:
	@echo "Available targets:"
	@echo "------------------"
	@for target in $(DEFAULT_TARGETS) $(TEST_PROGRAMS); do \
		echo -e "$$target";		\
	done

clean:
	rm -f *.a *.dll *.exe *.exp *.so \
		lib/*.o lib/*.obj lib/*.dllobj \
		programs/*.o programs/*.obj \
		$(DEFAULT_TARGETS) $(TEST_PROGRAMS) programs/config.h \
		libdeflate.lib libdeflatestatic.lib \
		.lib-cflags .prog-cflags

realclean: clean
	rm -f tags cscope* run_tests.log

FORCE:

.PHONY: all test_programs help clean realclean

.DEFAULT_GOAL = all
