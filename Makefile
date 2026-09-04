VERSION ?= 0.0.0
BUILD ?= dev

.PHONY: build test app run dmg lint clean

build:
	swift build

test:
	swift run MrMcLeanTests

app:
	bash Scripts/make-app.sh $(VERSION) $(BUILD)

run: app
	open dist/MrMcLean.app

dmg: app
	@ls -lh dist/*.dmg

clean:
	swift package clean
	rm -rf dist .build
