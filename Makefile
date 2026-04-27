.PHONY: test lint install
test:
	bats tests/
lint:
	shellcheck bin/cc-clocker lib/*.sh
install:
	./install.sh
