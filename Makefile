REVSION = $(shell git rev-list --count HEAD)
HTTP2REV = $(shell (cd $$GOPATH/src/github.com/phuslu/net/http2; git log --oneline -1 --format="%h"))

GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
CGO_ENABLED ?= 0

REPO = $(shell git rev-parse --show-toplevel)
PACKAGE = $(shell basename $(REPO))
ifeq ($(CGO_ENABLED), 0)
	BUILDROOT = $(REPO)/build/$(GOOS)_$(GOARCH)
else
	BUILDROOT = $(REPO)/build/$(GOOS)_$(GOARCH)_cgo
endif
STAGEDIR = $(BUILDROOT)/stage
OBJECTDIR = $(BUILDROOT)/obj
DISTDIR = $(BUILDROOT)/dist

ifeq ($(GOOS), windows)
	GOPROXY_EXE = $(PACKAGE).exe
	GOPROXY_STAGEDIR = $(STAGEDIR)
	GOPROXY_DISTCMD = 7za a -y -mx=9 -m0=lzma -mfb=128 -md=64m -ms=on
	GOPROXY_DISTEXT = .7z
else ifeq ($(GOOS), darwin)
	GOPROXY_EXE = $(PACKAGE)
	GOPROXY_STAGEDIR = $(STAGEDIR)
	GOPROXY_DISTCMD = BZIP=-9 tar cvjpf
	GOPROXY_DISTEXT = .tar.bz2
else ifneq (,$(findstring arm,$(GOARCH)))
	GOPROXY_EXE = $(PACKAGE)
	GOPROXY_STAGEDIR = $(STAGEDIR)
	GOPROXY_DISTCMD = BZIP=-9 tar cvjpf
	GOPROXY_DISTEXT = .tar.bz2
else ifneq (,$(findstring mips,$(GOARCH)))
	GOPROXY_EXE = $(PACKAGE)
	GOPROXY_STAGEDIR = $(STAGEDIR)
	GOPROXY_DISTCMD = GZIP=-9 tar cvzpf
	GOPROXY_DISTEXT = .tar.gz
else
	GOPROXY_EXE = $(PACKAGE)
	GOPROXY_STAGEDIR = $(STAGEDIR)/$(PACKAGE)
	GOPROXY_DISTCMD = XZ_OPT=-9 tar cvJpf
	GOPROXY_DISTEXT = .tar.xz
endif

GOPROXY_DIST = $(DISTDIR)/$(PACKAGE)_$(GOOS)_$(GOARCH)-r$(REVSION)$(GOPROXY_DISTEXT)
ifeq ($(CGO_ENABLED), 1)
	GOPROXY_DIST = $(DISTDIR)/$(PACKAGE)_$(GOOS)_$(GOARCH)_cgo-r$(REVSION)$(GOPROXY_DISTEXT)
endif

OBJECTS :=
OBJECTS += $(OBJECTDIR)/$(GOPROXY_EXE)

SOURCES :=
SOURCES += $(REPO)/README.md
SOURCES += $(REPO)/httpproxy/httpproxy.json
SOURCES += $(REPO)/httpproxy/filters/auth/auth.json
SOURCES += $(REPO)/httpproxy/filters/autoproxy/17monipdb.dat
SOURCES += $(REPO)/httpproxy/filters/autoproxy/autoproxy.json
SOURCES += $(REPO)/httpproxy/filters/autoproxy/gfwlist.txt
SOURCES += $(REPO)/httpproxy/filters/autoproxy/ip.html
SOURCES += $(REPO)/httpproxy/filters/autorange/autorange.json
SOURCES += $(REPO)/httpproxy/filters/direct/direct.json
SOURCES += $(REPO)/httpproxy/filters/gae/gae.json
SOURCES += $(REPO)/httpproxy/filters/php/php.json
SOURCES += $(REPO)/httpproxy/filters/rewrite/rewrite.json
SOURCES += $(REPO)/httpproxy/filters/stripssl/stripssl.json
SOURCES += $(REPO)/assets/packaging/gae.user.json.example

ifeq ($(GOOS)_$(GOARCH), windows_amd64)
	SOURCES += $(REPO)/assets/packaging/goproxy-gui.exe
	SOURCES += $(REPO)/assets/packaging/addto-startup.vbs
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.cmd
else ifeq ($(GOOS)_$(GOARCH), windows_386)
	SOURCES += $(REPO)/assets/packaging/goproxy-gui.exe
	SOURCES += $(REPO)/assets/packaging/addto-startup.vbs
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.cmd
else ifeq ($(GOOS)_$(GOARCH)_$(CGO_ENABLED), linux_arm_0)
	GOARM ?= 5
	SOURCES += $(REPO)/assets/packaging/goproxy.sh
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.sh
else ifeq ($(GOOS)_$(GOARCH)_$(CGO_ENABLED), linux_arm_1)
	GOARM ?= 5
	CC = $(or $(ARM_CC), arm-linux-gnueabihf-gcc)
	SOURCES += $(REPO)/assets/packaging/goproxy.sh
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.sh
else ifeq ($(GOOS), darwin)
	SOURCES += $(REPO)/assets/packaging/goproxy-macos.command
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.sh
else
	SOURCES += $(REPO)/assets/packaging/goproxy-gtk.py
	SOURCES += $(REPO)/assets/packaging/goproxy-gtk.png
	SOURCES += $(REPO)/assets/packaging/goproxy-gtk.desktop
	SOURCES += $(REPO)/assets/packaging/goproxy.sh
	SOURCES += $(REPO)/assets/packaging/get-latest-goproxy.sh
endif

.PHONY: build
build: $(GOPROXY_DIST)
	@ls -lht $(DISTDIR)

.PHONY: clean
clean:
	$(RM) -rf $(BUILDROOT)

$(GOPROXY_DIST): $(OBJECTS)
	mkdir -p $(DISTDIR) $(STAGEDIR) $(GOPROXY_STAGEDIR)
	cp $(OBJECTS) $(SOURCES) $(GOPROXY_STAGEDIR)
ifeq ($(GOOS)_$(GOARCH), $(shell go env GOOS)_$(shell go env GOARCH))
	GOPROXY_WAIT_SECONDS=0 $(GOPROXY_STAGEDIR)/$(GOPROXY_EXE)
endif
	cd $(STAGEDIR) && $(GOPROXY_DISTCMD) $@ *

$(OBJECTDIR)/$(GOPROXY_EXE):
	mkdir -p $(OBJECTDIR)
	env GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) CGO_ENABLED=$(CGO_ENABLED) CC=$(CC) \
	go build -v -ldflags="-s -w -X main.version=r$(REVSION) -X main.http2rev=$(HTTP2REV)" -o $@ .
