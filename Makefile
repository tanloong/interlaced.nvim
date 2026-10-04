NVIM ?= nvim
RVIM_ARGS = --headless --clean -u NONE --cmd 'set rtp+=.'
TESTS := $(wildcard tests/test_*.lua)

.PHONY: test doc

## Run every tests/test_*.lua with a clean Neovim.
test:
	@status=0; \
	for f in $(TESTS); do \
		echo "== $$f =="; \
		$(NVIM) $(RVIM_ARGS) -l "$$f" || status=1; \
	done; \
	exit $$status

## Regenerate doc/interlaced.nvim.txt from LuaCATS annotations.
## Requires vimcats: https://github.com/mrcjkb/vimcats
doc:
	vimcats --prefix-func --prefix-alias --prefix-class --prefix-type \
		$(wildcard lua/interlaced/*.lua) > doc/interlaced.nvim.txt
