.PHONY: all build release install clean run test

all: build

build:
	swift build

release:
	swift build -c release

install:
	./scripts/build_and_export_app.sh

run:
	swift run TorrentManager

test:
	swift run TorrentManager --test

search:
	swift run TorrentManager --search "$(q)"

clean:
	swift package clean
	rm -rf build .build

